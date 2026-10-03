package main

import "github.com/polymorfa/hypermeow/types/events"

func unavailableViewOnceEvent(event *events.UndecryptableMessage) *events.Message {
	if event.UnavailableType != events.UnavailableTypeViewOnce {
		return nil
	}
	return &events.Message{Info: event.Info, IsViewOnce: true}
}

func isViewOnceMessage(event *events.Message) bool {
	message := unwrapMessage(event.Message)
	return event.IsViewOnce || message.GetImageMessage().GetViewOnce() ||
		message.GetVideoMessage().GetViewOnce() || message.GetAudioMessage().GetViewOnce()
}

func addDisappearingMessageMetadata(payload map[string]interface{}, event *events.Message, hasAttachments bool) {
	if isViewOnceMessage(event) {
		payload["view_once"] = true
		payload["view_once_unavailable"] = !hasAttachments
	}
	if event.IsEphemeral || extractContextInfo(event.Message).GetExpiration() > 0 {
		payload["ephemeral"] = true
	}
}
