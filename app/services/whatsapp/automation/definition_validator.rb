# rubocop:disable Metrics/ClassLength
class Whatsapp::Automation::DefinitionValidator
  # Graph validation is intentionally branch-heavy because each node type has
  # a compact, explicit contract.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
  SUPPORTED_NODE_TYPES = %w[trigger message media location contact wait condition action end].freeze
  MEDIA_TYPES = %w[audio image video document sticker].freeze
  MEDIA_CONTENT_TYPES = {
    'audio' => %w[audio/aac audio/mp4 audio/mpeg audio/amr audio/ogg audio/opus],
    'image' => %w[image/jpeg image/png],
    'video' => %w[video/mp4 video/3gpp],
    'document' => Attachment::ACCEPTABLE_FILE_TYPES,
    'sticker' => %w[image/webp]
  }.freeze
  MEDIA_SIZE_LIMITS = {
    'audio' => 16.megabytes,
    'image' => 5.megabytes,
    'video' => 16.megabytes,
    'document' => 100.megabytes,
    'sticker' => 100.kilobytes
  }.freeze
  CONDITION_FIELDS = %w[last_button_id name email phone_number].freeze
  CONDITION_OPERATORS = %w[equals not_equals contains present].freeze
  ACTIONS = %w[
    add_label remove_label open_conversation resolve_conversation
    opt_out_whatsapp opt_in_whatsapp
  ].freeze

  def initialize(definition, publish: false)
    @definition = definition
    @publish = publish
    @errors = []
  end

  def validate
    return ['must be an object'] unless definition.is_a?(Hash)

    validate_collections
    return errors if errors.any?

    validate_nodes
    validate_edges
    validate_publishable_graph if publish
    errors.uniq
  end

  private

  attr_reader :definition, :errors, :publish

  def nodes
    @nodes ||= definition['nodes'] || definition[:nodes]
  end

  def edges
    @edges ||= definition['edges'] || definition[:edges]
  end

  def validate_collections
    errors << 'nodes must be an array' unless nodes.is_a?(Array)
    errors << 'edges must be an array' unless edges.is_a?(Array)
  end

  def validate_nodes
    ids = nodes.filter_map { |node| node['id'] || node[:id] }
    errors << 'node ids must be present and unique' unless ids.length == nodes.length && ids.uniq.length == ids.length

    nodes.each do |node|
      type = node['type'] || node[:type]
      config = (node['config'] || node[:config] || {}).with_indifferent_access
      errors << "node #{node['id'] || node[:id]} has an unsupported type" unless SUPPORTED_NODE_TYPES.include?(type)
      validate_node_config(node['id'] || node[:id], type, config)
    end
  end

  def validate_node_config(id, type, config)
    case type
    when 'trigger'
      validate_reply_buttons(id, config)
    when 'message'
      validate_message_node(id, config)
    when 'media'
      validate_media_node(id, config)
    when 'location'
      validate_location_node(id, config)
    when 'contact'
      validate_contact_node(id, config)
    when 'wait'
      duration = config[:duration].to_i
      errors << "wait node #{id} needs a duration between 1 and 43,200 minutes" if publish && !duration.between?(1, 43_200)
    when 'condition'
      errors << "condition node #{id} needs a field" if publish && config[:field].blank?
      errors << "condition node #{id} needs an operator" if publish && config[:operator].blank?
      errors << "condition node #{id} has an unsupported field" if config[:field].present? && !supported_condition_field?(config[:field])
      errors << "condition node #{id} has an unsupported operator" if config[:operator].present? && CONDITION_OPERATORS.exclude?(config[:operator])
      errors << "condition node #{id} needs a comparison value" if publish && config[:operator] != 'present' && config[:value].blank?
    when 'action'
      errors << "action node #{id} needs an action" if publish && config[:action].blank?
      errors << "action node #{id} has an unsupported action" if config[:action].present? && ACTIONS.exclude?(config[:action])
      errors << "action node #{id} needs a label" if publish && config[:action].in?(%w[add_label remove_label]) && config[:value].blank?
    end
  end

  def validate_message_node(id, config)
    mode = config[:mode].presence || 'session'
    errors << "message node #{id} has an unsupported mode" unless %w[session template].include?(mode)
    errors << "message node #{id} needs text" if publish && mode == 'session' && config[:text].blank?
    errors << "message node #{id} exceeds 4,096 characters" if mode == 'session' && config[:text].to_s.length > 4096
    errors << "template node #{id} needs a template name" if publish && mode == 'template' && config[:template_name].blank?
    validate_template_variables(id, config) if publish && mode == 'template'

    validate_reply_buttons(id, config)
  end

  def validate_reply_buttons(id, config)
    buttons = Array(config[:buttons])
    errors << "message node #{id} supports at most ten interactive options" if buttons.length > 10
    return if buttons.empty?

    button_ids = buttons.map { |button| button['id'] || button[:id] }
    button_titles = buttons.map { |button| button['title'] || button[:title] }
    valid_button_ids = button_ids.length == buttons.length && button_ids.uniq.length == button_ids.length
    errors << "message node #{id} button ids must be present and unique" unless valid_button_ids && button_ids.all?(&:present?)
    errors << "message node #{id} button titles must be present" if publish && !button_titles.all?(&:present?)
    title_limit = buttons.length > 3 ? 24 : 20
    return unless button_titles.any? { |title| title.to_s.length > title_limit }

    errors << "message node #{id} option titles cannot exceed #{title_limit} characters"
  end

  def validate_media_node(id, config)
    media_type = config[:media_type].to_s
    errors << "media node #{id} has an unsupported media type" unless MEDIA_TYPES.include?(media_type)
    errors << "media node #{id} needs an uploaded file" if publish && config[:blob_signed_id].blank?
    return if config[:blob_signed_id].blank? || MEDIA_TYPES.exclude?(media_type)

    blob = ActiveStorage::Blob.find_signed(config[:blob_signed_id])
    errors << "media node #{id} has an invalid uploaded file" and return if blob.blank?

    allowed_types = MEDIA_CONTENT_TYPES.fetch(media_type)
    errors << "media node #{id} has an unsupported file format" unless allowed_types.include?(blob.content_type)
    errors << "media node #{id} exceeds the WhatsApp size limit" if blob.byte_size > MEDIA_SIZE_LIMITS.fetch(media_type)
    is_voice_message = ActiveModel::Type::Boolean.new.cast(config[:is_voice_message])
    return unless is_voice_message && %w[audio/ogg audio/opus].exclude?(blob.content_type)

    errors << "media node #{id} voice notes require OGG/Opus audio"
  end

  def validate_location_node(id, config)
    latitude = Float(config[:latitude], exception: false)
    longitude = Float(config[:longitude], exception: false)
    errors << "location node #{id} needs a latitude between -90 and 90" if publish && (latitude.nil? || !latitude.between?(-90, 90))
    errors << "location node #{id} needs a longitude between -180 and 180" if publish && (longitude.nil? || !longitude.between?(-180, 180))
  end

  def validate_contact_node(id, config)
    errors << "contact node #{id} needs a name" if publish && config[:name].blank?
    errors << "contact node #{id} needs a phone number" if publish && config[:phone].blank?
  end

  def validate_edges
    node_ids = nodes.filter_map { |node| node['id'] || node[:id] }.to_set
    edges.each do |edge|
      source = edge['source'] || edge[:source]
      target = edge['target'] || edge[:target]
      errors << "edge #{edge['id'] || edge[:id]} has an unknown source" unless node_ids.include?(source)
      errors << "edge #{edge['id'] || edge[:id]} has an unknown target" unless node_ids.include?(target)
    end
  end

  def validate_publishable_graph
    errors << 'needs exactly one trigger node' unless nodes.count { |node| (node['type'] || node[:type]) == 'trigger' } == 1
    has_outgoing_node = nodes.any? { |node| (node['type'] || node[:type]).in?(%w[message media location contact]) }
    errors << 'needs at least one outgoing message node' unless has_outgoing_node
    errors << 'contains a cycle; published flows must terminate' if cyclic?
    validate_connections
    validate_reachability
  end

  def validate_template_variables(id, config)
    variable_ids = config[:preview_text].to_s.scan(/\{\{([^}]+)\}\}/).flatten.map(&:strip).uniq
    return if variable_ids.empty?

    body_params = config.dig(:processed_params, :body).to_h.with_indifferent_access
    missing_ids = variable_ids.reject { |variable_id| body_params[variable_id].present? }
    errors << "template node #{id} needs values for variables #{missing_ids.join(', ')}" if missing_ids.any?
  end

  def supported_condition_field?(field)
    CONDITION_FIELDS.include?(field) || field.to_s.start_with?('custom.')
  end

  def validate_connections
    grouped_edges = edges.group_by do |edge|
      [edge['source'] || edge[:source], (edge['source_handle'] || edge[:source_handle]).presence || 'default']
    end
    grouped_edges.each do |(source, handle), records|
      errors << "node #{source} has more than one connection from #{handle}" if records.length > 1
    end

    nodes.each do |node|
      id = node['id'] || node[:id]
      type = node['type'] || node[:type]
      config = (node['config'] || node[:config] || {}).with_indifferent_access
      expected_handles = expected_source_handles(type, config)
      expected_handles.each do |handle|
        errors << "node #{id} needs a connection from #{handle}" if grouped_edges[[id, handle]].blank?
      end
    end
  end

  def expected_source_handles(type, config)
    return [] if type == 'end'
    return %w[true false] if type == 'condition'

    buttons = Array(config[:buttons])
    return buttons.filter_map { |button| button['id'] || button[:id] } if type.in?(%w[trigger message]) && buttons.any?

    ['default']
  end

  def validate_reachability
    trigger = nodes.find { |node| (node['type'] || node[:type]) == 'trigger' }
    return if trigger.blank?

    adjacency = edges.group_by { |edge| edge['source'] || edge[:source] }
    reachable = Set.new
    queue = [trigger['id'] || trigger[:id]]
    until queue.empty?
      current = queue.shift
      next unless reachable.add?(current)

      queue.concat(Array(adjacency[current]).map { |edge| edge['target'] || edge[:target] })
    end
    unreachable = nodes.filter_map do |node|
      id = node['id'] || node[:id]
      id unless reachable.include?(id)
    end
    errors << "contains unreachable nodes: #{unreachable.join(', ')}" if unreachable.any?
  end

  def cyclic?
    adjacency = edges.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |edge, graph|
      graph[edge['source'] || edge[:source]] << (edge['target'] || edge[:target])
    end
    visiting = Set.new
    visited = Set.new

    nodes.any? do |node|
      cyclic_from?(node['id'] || node[:id], adjacency, visiting, visited)
    end
  end

  def cyclic_from?(node_id, adjacency, visiting, visited)
    return true if visiting.include?(node_id)
    return false if visited.include?(node_id)

    visiting.add(node_id)
    found_cycle = adjacency[node_id].any? { |target| cyclic_from?(target, adjacency, visiting, visited) }
    visiting.delete(node_id)
    visited.add(node_id)
    found_cycle
  end

  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
end
# rubocop:enable Metrics/ClassLength
