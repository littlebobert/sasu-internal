import SwiftUI

struct AnswerPanelView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            answerBody
            Divider()
            followUp
        }
        .padding(18)
        .frame(minWidth: 420, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(appModel.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer()

                if appModel.isRequestInFlight {
                    ProgressView()
                        .controlSize(.small)

                    Button("Stop") {
                        appModel.stopCurrentRequest()
                    }
                    .fixedSize()
                }
            }

            HStack(spacing: 6) {
                Button("Capture Screen") {
                    appModel.captureAndAsk()
                }
                .disabled(appModel.isRequestInFlight)
                .fixedSize()

                Button("Translate Clipboard") {
                    appModel.translateClipboard()
                }
                .disabled(appModel.isRequestInFlight)
                .fixedSize()

                Button("Copy Answer") {
                    appModel.copyLastAnswerToPasteboard()
                }
                .disabled(appModel.lastResponse == nil)
                .fixedSize()

                Button("Clear") {
                    appModel.clearTranscript()
                }
                .disabled(appModel.transcriptMessages.isEmpty || appModel.isRequestInFlight)
                .fixedSize()
            }

        }
    }

    @ViewBuilder
    private var answerBody: some View {
        if !appModel.transcriptMessages.isEmpty {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(appModel.transcriptMessages) { message in
                            VStack(alignment: .leading, spacing: 12) {
                                TranscriptMessageView(message: message)

                                if let highlight = message.actionSuggestion {
                                    highlightSummary(
                                        highlight,
                                        isCurrentSuggestion: highlight == appModel.currentHighlightSuggestion
                                    )
                                }
                            }
                            .id(message.id)
                        }

                        if appModel.shouldOfferPermissionRelaunch, appModel.errorMessage != nil {
                            Button("Relaunch Sasu") {
                                appModel.relaunchSasu()
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("transcript-bottom")
                    }
                    .padding(.trailing, 8)
                }
                .onChange(of: appModel.transcriptMessages.count) { _ in
                    scrollTranscriptToBottom(proxy)
                }
                .onChange(of: appModel.currentHighlightSuggestion) { _ in
                    scrollTranscriptToBottom(proxy)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Waiting for the first screen capture...")
                    .foregroundStyle(.secondary)
                Text("On your command, Sasu will capture your screen, then wait for your question before sending anything.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func scrollTranscriptToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("transcript-bottom", anchor: .bottom)
            }
        }
    }

    private func highlightSummary(
        _ highlight: HighlightSuggestion,
        isCurrentSuggestion: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Suggested highlight: \(highlight.label)")
                    .font(.caption.bold())

                Spacer()

                Button(isCurrentSuggestion && appModel.isHighlightVisible ? "Hide" : "Show") {
                    if appModel.isHighlightVisible {
                        appModel.hideHighlight()
                    } else {
                        appModel.showHighlight()
                    }
                }
                .disabled(appModel.isRequestInFlight || !isCurrentSuggestion)
                .fixedSize()
            }

            if let reason = highlight.reason, !reason.isEmpty {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isCurrentSuggestion && appModel.isHighlightVisible {
                Text("Auto-hides after 5 seconds.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.top, 2)
    }

    private var followUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(appModel.isScreenshotPrepared && appModel.lastResponse == nil ? "Question" : "Follow-up")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                SelectAllTextField(
                    text: $appModel.followUpText,
                    placeholder: appModel.isScreenshotPrepared
                        ? "Ask about this screenshot..."
                        : "Capture a screenshot first...",
                    selectAllTrigger: appModel.querySelectionNonce,
                    isEnabled: !appModel.isRequestInFlight,
                    onSubmit: {
                        appModel.sendFollowUp()
                    }
                )
                .frame(height: 44)

                Button("Send") {
                    appModel.sendFollowUp()
                }
                .disabled(appModel.isRequestInFlight || appModel.followUpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

private struct TranscriptMessageView: View {
    @EnvironmentObject private var appModel: AppModel
    let message: ChatTranscriptMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role.rawValue)
                .font(.caption.bold())
                .foregroundStyle(roleColor)

            if let image = message.image {
                HStack(alignment: .top, spacing: 10) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 76)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                        }
                        .onTapGesture(count: 2) {
                            if let imageData = message.imageData {
                                appModel.showScreenshotWindow(imageData: imageData)
                            }
                        }
                        .help("Double-click to open screenshot")

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screenshot prepared")
                            .font(.caption.bold())
                        Text(message.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
            } else if let clipboardSourceText {
                (Text("Clipboard text: ") + Text(clipboardSourceText))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownText(markdown: message.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var roleColor: Color {
        switch message.role {
        case .user:
            return .secondary
        case .screenshot:
            return .secondary
        case .assistant:
            return .primary
        case .error:
            return .red
        }
    }

    private var clipboardSourceText: String? {
        let prefix = "Clipboard text: "
        guard message.role == .user, message.text.hasPrefix(prefix) else {
            return nil
        }

        return String(message.text.dropFirst(prefix.count))
    }
}
