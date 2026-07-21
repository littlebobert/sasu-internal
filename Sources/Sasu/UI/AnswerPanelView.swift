import SwiftUI

struct AnswerPanelView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var shouldAutoScrollTranscript = true

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            if appModel.isFirstLaunchOnboardingVisible {
                onboardingBody
            } else {
                answerBody
                Divider()
                followUp
            }
        }
        .padding(appModel.isFirstLaunchOnboardingVisible ? 14 : 18)
        .frame(minWidth: 420, minHeight: appModel.isFirstLaunchOnboardingVisible ? 430 : 420)
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
        }
    }

    private var onboardingBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            onboardingLanguagePairPicker

            Divider()

            Text("Try Sasu on this example")
                .font(.title3.bold())

            HStack(alignment: .top, spacing: 16) {
                onboardingDocument
                    .frame(maxWidth: .infinity, alignment: .top)

                onboardingExplanation
                    .frame(maxWidth: .infinity, alignment: .top)
            }

            Text("When you’re ready, click the Japanese button. Then Sasu will ask macOS for Screen Recording permission.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Have questions? Contact me (the developer).") {
                appModel.contactDeveloperAboutOnboarding()
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var onboardingLanguagePairPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose the language you translate from")
                .font(.title3.bold())

            Picker("Translate from", selection: $appModel.translationSourceLanguage) {
                ForEach(TranslationDirection.availableSourceLanguagesForUserInterface) { sourceLanguage in
                    Text(sourceLanguage.label).tag(sourceLanguage)
                }
            }
            .frame(maxWidth: 420)

            let direction = TranslationDirection.forUserInterface(
                sourceLanguage: appModel.translationSourceLanguage
            )
            Text("Sasu reads \(direction.localizedExpectedSourceLanguage) into \(direction.localizedTargetLanguage), and translates editable text in the reverse direction. You can change this later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var onboardingDocument: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("日本語のサンプル")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text("Sasuへようこそ。")
                .font(.title3.bold())

            Text("日本語のページやフォームで迷ったとき、Sasuが画面上で意味と次に押す場所を案内します。")
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            if appModel.isOnboardingGuidanceVisible {
                Text("Click this green button to get started.")
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
            }

            Button {
                appModel.completeFirstLaunchOnboarding()
            } label: {
                Text("Sasuを始める")
                    .font(.body.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .foregroundStyle(.white)
                    .background(Color.green)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .overlay {
                if appModel.isOnboardingGuidanceVisible {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 4)
                        .padding(-6)
                        .allowsHitTesting(false)
                }
            }
            .shadow(color: appModel.isOnboardingGuidanceVisible ? Color.blue.opacity(0.35) : .clear, radius: 8)
        }
        .padding(14)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        }
    }

    private var onboardingExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sasu")
                .font(.caption.bold())
                .foregroundStyle(.primary)

            Text("This is a welcome message for Sasu. It says Sasu helps explain Japanese pages and forms, then points to the next place to click. The green button means “Start using Sasu.”")
                .fixedSize(horizontal: false, vertical: true)

            Button(
                appModel.isOnboardingGuidanceVisible
                    ? LocalizedStringResource("Hide guidance")
                    : LocalizedStringResource("Show me where to click")
            ) {
                if appModel.isOnboardingGuidanceVisible {
                    appModel.hideOnboardingGuidance()
                } else {
                    appModel.showOnboardingGuidance()
                }
            }
            .fixedSize()

            if appModel.isOnboardingGuidanceVisible {
                Text("Click `Sasuを始める` to start using Sasu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var answerBody: some View {
        if !appModel.transcriptMessages.isEmpty {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(appModel.transcriptMessages) { message in
                                VStack(alignment: .leading, spacing: 12) {
                                    TranscriptMessageView(
                                        message: message,
                                        availableWidth: max(300, geometry.size.width - 32),
                                        onUserScroll: suspendTranscriptAutoScroll
                                    )

                                    if let highlight = message.actionSuggestion {
                                        highlightSummary(
                                            highlight,
                                            isCurrentSuggestion: highlight == appModel.currentHighlightSuggestion
                                        )
                                    }
                                }
                                .id(message.id)
                            }

                            if !appModel.streamingResponseText.isEmpty {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Sasu")
                                        .font(.caption.bold())
                                        .foregroundStyle(.blue)

                                    MarkdownText(
                                        markdown: appModel.streamingResponseText,
                                        fontSize: appModel.transcriptFontSize,
                                        onUserScroll: suspendTranscriptAutoScroll
                                    )
                                    .frame(
                                        width: max(300, geometry.size.width - 32),
                                        alignment: .leading
                                    )
                                    .fixedSize(horizontal: false, vertical: true)
                                }
                                .id("streaming-response")
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
                        guard shouldAutoScrollTranscript else { return }
                        scrollTranscriptToBottomAfterLayoutSettles(proxy)
                    }
                    .onChange(of: appModel.isRequestInFlight) { isRequestInFlight in
                        guard isRequestInFlight else { return }
                        shouldAutoScrollTranscript = true
                        scrollTranscriptToBottomAfterLayoutSettles(proxy)
                    }
                    .onChange(of: appModel.currentHighlightSuggestion) { _ in
                        guard shouldAutoScrollTranscript else { return }
                        scrollTranscriptToBottom(proxy)
                    }
                    .onChange(of: appModel.streamingResponseText) { text in
                        guard !text.isEmpty, shouldAutoScrollTranscript else { return }
                        scrollTranscriptToBottomAfterLayoutSettles(proxy, animated: false)
                    }
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

    private func scrollTranscriptToBottomAfterLayoutSettles(
        _ proxy: ScrollViewProxy,
        animated: Bool = true
    ) {
        let scroll = {
            proxy.scrollTo("transcript-bottom", anchor: .bottom)
        }

        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2), scroll)
            } else {
                scroll()
            }
        }

        for delay in [0.05, 0.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard shouldAutoScrollTranscript else { return }
                if animated {
                    withAnimation(.easeOut(duration: 0.15), scroll)
                } else {
                    scroll()
                }
            }
        }
    }

    private func suspendTranscriptAutoScroll() {
        shouldAutoScrollTranscript = false
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

                Button(
                    isCurrentSuggestion && appModel.isHighlightVisible
                        ? LocalizedStringResource("Hide")
                        : LocalizedStringResource("Show")
                ) {
                    if appModel.isHighlightVisible {
                        appModel.hideHighlight()
                    } else {
                        appModel.showHighlight(highlight)
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
        .textSelection(.enabled)
    }

    private var followUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                appModel.lastResponse == nil
                    ? LocalizedStringResource("Question")
                    : LocalizedStringResource("Follow-up")
            )
            .font(.caption.bold())
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 8) {
                SelectAllTextField(
                    text: $appModel.followUpText,
                    placeholder: appModel.isScreenshotPrepared
                        ? String(localized: "Ask about this screenshot...")
                        : String(localized: "Capture a screenshot first..."),
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
    let availableWidth: CGFloat
    let onUserScroll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(message.role.displayLabel)
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

                    Text(message.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if let browserPageContext = message.browserPageContext {
                        safariPageIncludedBadge(browserPageContext)
                    } else if let browserPageCaptureIssue = message.browserPageCaptureIssue {
                        safariPageIssueBadge(browserPageCaptureIssue)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let sourceTextDetails {
                sourceTextView(
                    sourceTextDetails.text,
                    label: sourceTextDetails.label
                )
            } else {
                MarkdownText(
                    markdown: message.text,
                    fontSize: appModel.transcriptFontSize,
                    onUserScroll: onUserScroll
                )
                    .frame(width: availableWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private func sourceTextView(_ text: String, label: String) -> some View {
        if let sourceReadings = usefulSourceReadings {
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                RubyTextView(segments: sourceReadings, fontSize: appModel.transcriptFontSize)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            (Text("\(label) ") + Text(text))
                .font(.system(size: appModel.transcriptFontSize))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var usefulSourceReadings: [RubyTextSegment]? {
        guard let sourceReadings = message.sourceReadings,
              sourceReadings.contains(where: { $0.reading?.isEmpty == false }) else {
            return nil
        }

        return sourceReadings
    }

    private func safariPageIncludedBadge(_ context: BrowserPageContext) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Full Safari page included")
                .font(.caption.bold())
                .foregroundStyle(.green)

            Text("\(context.text.count) characters from \(context.displayTitle)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.green.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help("Sasu included extracted Safari page text from below the visible viewport.")
    }

    private func safariPageIssueBadge(_ issue: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Safari page not included")
                .font(.caption.bold())
                .foregroundStyle(.orange)

            Text(issue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help(issue)
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

    private var sourceTextDetails: (label: String, text: String)? {
        guard message.role == .user, let sourceKind = message.sourceKind else { return nil }
        return (sourceKind.displayLabel, message.text)
    }
}
