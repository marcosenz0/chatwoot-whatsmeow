class Whatsapp::Automation::DefinitionValidator
  # Graph validation is intentionally branch-heavy because each node type has
  # a compact, explicit contract.
  # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  SUPPORTED_NODE_TYPES = %w[trigger message wait condition action end].freeze

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
    when 'message'
      validate_message_node(id, config)
    when 'wait'
      duration = config[:duration].to_i
      errors << "wait node #{id} needs a duration between 1 and 43,200 minutes" unless duration.between?(1, 43_200)
    when 'condition'
      errors << "condition node #{id} needs a field" if config[:field].blank?
      errors << "condition node #{id} needs an operator" if config[:operator].blank?
    when 'action'
      errors << "action node #{id} needs an action" unless %w[add_label remove_label open_conversation resolve_conversation].include?(config[:action])
    end
  end

  def validate_message_node(id, config)
    mode = config[:mode].presence || 'session'
    errors << "message node #{id} has an unsupported mode" unless %w[session template].include?(mode)
    errors << "message node #{id} needs text" if mode == 'session' && config[:text].blank?
    errors << "template node #{id} needs a template name" if mode == 'template' && config[:template_name].blank?

    buttons = Array(config[:buttons])
    errors << "message node #{id} supports at most three reply buttons" if buttons.length > 3
    return if buttons.empty?

    button_ids = buttons.filter_map { |button| button['id'] || button[:id] }
    button_titles = buttons.filter_map { |button| button['title'] || button[:title] }
    valid_button_ids = button_ids.length == buttons.length && button_ids.uniq.length == button_ids.length
    errors << "message node #{id} button ids must be present and unique" unless valid_button_ids
    errors << "message node #{id} button titles must be present" unless button_titles.length == buttons.length
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
    errors << 'needs at least one message node' unless nodes.any? { |node| (node['type'] || node[:type]) == 'message' }
    errors << 'contains a cycle; published flows must terminate' if cyclic?
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

  # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
end
