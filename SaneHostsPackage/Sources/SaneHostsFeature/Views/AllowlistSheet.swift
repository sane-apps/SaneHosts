import SaneUI
import SwiftUI

struct AllowlistSheet: View {
    let initial: HostAllowlist
    let protectionIsActive: Bool
    let onSave: (HostAllowlist) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var draft: HostAllowlist
    @State private var input = ""
    @State private var inputError: String?
    @FocusState private var inputFocused: Bool

    init(initial: HostAllowlist, protectionIsActive: Bool, onSave: @escaping (HostAllowlist) -> Void) {
        self.initial = initial
        self.protectionIsActive = protectionIsActive
        self.onSave = onSave
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Allowed Sites")
                    .font(.headline)
                    .foregroundColor(.white)
            }

            Text("Sites here are never blocked, even when a list includes them. Each site also covers its subdomains.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)

            CompactSection("Sites", icon: "globe", iconColor: .green) {
                if draft.isEmpty {
                    Text("No allowed sites yet.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(draft.domains.enumerated()), id: \.element) { index, domain in
                                domainRow(domain)
                                if index < draft.domains.count - 1 {
                                    CompactDivider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    TextField("example.com", text: $input)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .padding(10)
                        .background(colorScheme == .dark ? Color.white.opacity(0.08) : Color.white)
                        .cornerRadius(8)
                        .focused($inputFocused)
                        .onSubmit(addInput)
                        .accessibilityLabel("Site to allow")

                    Button("Add", action: addInput)
                        .buttonStyle(SaneActionButtonStyle())
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if let inputError {
                    Text(inputError)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SaneActionButtonStyle())

                Button(protectionIsActive ? "Save & Apply" : "Save") {
                    addInputIfPresent()
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SaneActionButtonStyle(prominent: true))
                .disabled(draft == initial && input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(SaneGradientBackground())
        .onAppear { inputFocused = true }
    }

    private func domainRow(_ domain: String) -> some View {
        HStack {
            Text(domain)
                .font(.body)
                .foregroundColor(.white)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                draft.remove(domain)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .help("Remove \(domain)")
            .accessibilityLabel("Remove \(domain)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func addInput() {
        let pieces = input
            .components(separatedBy: CharacterSet(charactersIn: ", \n\t"))
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else { return }

        var rejected: [String] = []
        for piece in pieces {
            if HostAllowlist.normalize(piece) == nil {
                rejected.append(piece)
            } else {
                draft.add(piece)
            }
        }

        if rejected.isEmpty {
            input = ""
            inputError = nil
        } else {
            input = rejected.joined(separator: " ")
            inputError = "“\(rejected[0])” isn’t a website address. Try something like example.com."
        }
    }

    private func addInputIfPresent() {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        addInput()
    }
}
