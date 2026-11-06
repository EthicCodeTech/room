import SwiftUI
import RoomCore

struct AskView: View {
    @Bindable var model: AppModel
    @State private var draft = ""

    private let suggestions = ["What grew this week?", "What is safe to delete?", "Why is my disk full?"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow(text: "Ask")
                            Text("Ask about your storage").dsText(Token.h1)
                            HStack(spacing: 10) {
                                DSBadge(text: model.advisor.name, dot: model.advisor.name == "Built-in rules" ? DS.neutralDot : Color(hex: Token.successText))
                                Text(note).dsText(Token.small, color: DS.textMuted)
                            }
                        }
                        if model.messages.isEmpty {
                            HStack(spacing: 8) { ForEach(suggestions, id: \.self) { s in
                                Button { model.ask(s) } label: {
                                    Text(s).font(.ds(.init(13, 500))).foregroundStyle(DS.textSoft).padding(.horizontal, 14).frame(height: 32)
                                        .overlay(Capsule().strokeBorder(DS.lineStrong, lineWidth: Token.hairline))
                                }.buttonStyle(.plain)
                            } }
                        }
                        ForEach(model.messages) { m in bubble(m).id(m.id).transition(.rise) }
                        if model.isAsking { HStack(spacing: 10) { InlineSpinner(); Text("Thinking").dsText(Token.small, color: DS.textMuted) }.transition(.rise) }
                    }
                    .motion(.panel, value: model.messages.count).motion(.panel, value: model.isAsking)
                    .frame(maxWidth: 760, alignment: .leading).padding(32).padding(.top, 76).frame(maxWidth: .infinity)
                }
                .onChange(of: model.messages.count) { _, _ in if let last = model.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } } }
            }
            Rectangle().fill(DS.line).frame(height: Token.hairline)
            HStack(spacing: 12) {
                TextField("", text: $draft, prompt: Text("Ask a question, like \u{201C}what grew this week?\u{201D}").foregroundStyle(DS.placeholder))
                    .textFieldStyle(DSFieldStyle()).onSubmit(send).accessibilityLabel("Question")
                PillButton(title: "Ask", isLoading: model.isAsking, action: send).disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }.padding(.horizontal, 32).padding(.vertical, 16).frame(maxWidth: 824).frame(maxWidth: .infinity)
        }
    }

    private var note: String {
        switch model.settings.advisorMode {
        case .off: "The assistant is off. Answers come from built-in rules."
        case .onDevice: model.advisor.name == "Built-in rules" ? "On-device assistant isn't available on this Mac, so built-in rules answer." : "Runs on this Mac. Nothing leaves it."
        case .claude: model.advisor.name == "Built-in rules" ? "Add an API key in Settings to use Claude." : "Only sizes, categories and generic names are sent. Never file names or paths."
        }
    }

    private func send() { let q = draft; draft = ""; Haptics.play(.select); model.ask(q) }

    private func bubble(_ m: ChatMessage) -> some View {
        VStack(alignment: m.role == .user ? .trailing : .leading, spacing: 6) {
            Text(m.text).dsText(Token.body, color: DS.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: Token.radiusMD, style: .continuous).fill(m.role == .user ? DS.raised : DS.card))
                .overlay(RoundedRectangle(cornerRadius: Token.radiusMD, style: .continuous).strokeBorder(DS.line, lineWidth: Token.hairline))
            if let s = m.source { Text(s).dsText(Token.micro, color: DS.textFaint) }
        }.frame(maxWidth: .infinity, alignment: m.role == .user ? .trailing : .leading)
    }
}
