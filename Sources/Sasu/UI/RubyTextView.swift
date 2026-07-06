import SwiftUI
import WebKit

struct RubyTextView: View {
    let segments: [RubyTextSegment]
    @State private var height: CGFloat = 44

    var body: some View {
        RubyWebView(segments: segments, height: $height)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RubyWebView: NSViewRepresentable {
    let segments: [RubyTextSegment]
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = ScrollPassthroughWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = Self.html(for: segments)
        guard context.coordinator.currentHTML != html else { return }
        context.coordinator.currentHTML = html
        webView.loadHTMLString(html, baseURL: nil)
    }

    private static func html(for segments: [RubyTextSegment]) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        html, body {
          margin: 0;
          padding: 0;
          background: transparent;
          color: -apple-system-label;
          font: 13px -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Yu Gothic", sans-serif;
          line-height: 1.8;
          overflow: hidden;
          -webkit-user-select: text;
          user-select: text;
        }
        ruby { ruby-position: over; }
        rt {
          color: -apple-system-secondary-label;
          font-size: 0.65em;
          line-height: 1;
        }
        </style>
        </head>
        <body>\(segments.map(htmlSegment).joined())</body>
        </html>
        """
    }

    private static func htmlSegment(_ segment: RubyTextSegment) -> String {
        let text = escapeHTML(segment.text)
        guard let reading = segment.reading?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reading.isEmpty else {
            return text
        }

        return "<ruby><rb>\(text)</rb><rt>\(escapeHTML(reading))</rt></ruby>"
    }

    private static func escapeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
            .replacingOccurrences(of: "\n", with: "<br>")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var currentHTML = ""
        private var height: Binding<CGFloat>

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("Math.ceil(document.body.scrollHeight)") { [weak self] result, _ in
                guard let self else { return }
                let measuredHeight: CGFloat
                if let number = result as? NSNumber {
                    measuredHeight = CGFloat(truncating: number)
                } else {
                    measuredHeight = 44
                }

                DispatchQueue.main.async {
                    self.height.wrappedValue = max(44, measuredHeight)
                }
            }
        }
    }
}

private final class ScrollPassthroughWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        guard let outerScrollView = ancestorScrollView() else {
            super.scrollWheel(with: event)
            return
        }

        outerScrollView.scrollWheel(with: event)
    }

    private func ancestorScrollView() -> NSScrollView? {
        var ancestor = superview
        while let current = ancestor {
            if let scrollView = current as? NSScrollView {
                return scrollView
            }
            ancestor = current.superview
        }

        return nil
    }
}
