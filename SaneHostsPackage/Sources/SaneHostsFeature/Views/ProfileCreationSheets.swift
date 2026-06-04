import AppKit
import SaneUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - New Profile Sheet

struct NewProfileSheet: View {
    let store: ProfileStore
    let onCreated: (Profile) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var name = ""
    @State private var selectedColor: ProfileColor = .blue

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: SaneIcons.add)
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("New Profile")
                    .font(.headline)
            }

            // Form
            VStack(spacing: 16) {
                CompactSection("Profile Name", icon: "textformat", iconColor: .blue) {
                    TextField("My Profile", text: $name)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }

                CompactSection("Color Tag", icon: "paintpalette", iconColor: .purple) {
                    HStack(spacing: 12) {
                        ForEach(ProfileColor.allCases, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                Circle()
                                    .fill(colorForTag(color))
                                    .frame(width: 24, height: 24)
                                    .overlay {
                                        if selectedColor == color {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Select \(color.rawValue) color")
                            .accessibilityAddTraits(selectedColor == color ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(SaneActionButtonStyle())

                Button("Create") {
                    Task {
                        if let profile = try? await store.create(name: name) {
                            onCreated(profile)
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(SaneActionButtonStyle(prominent: true))
                .disabled(name.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(SaneGradientBackground())
    }

    private func colorForTag(_ tag: ProfileColor) -> Color {
        tag.uiColor
    }
}

// MARK: - Template Picker

struct TemplatePickerSheet: View {
    let store: ProfileStore
    let onCreated: (Profile) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: "doc.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Create from Template")
                    .font(.headline)
            }

            // Templates
            VStack(spacing: 12) {
                ForEach(ProfileTemplate.allCases, id: \.name) { template in
                    TemplateRow(template: template) {
                        Task {
                            if let profile = try? await store.create(name: template.name, from: template) {
                                onCreated(profile)
                                dismiss()
                            }
                        }
                    }
                }
            }

            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(SaneActionButtonStyle())
            .accessibilityLabel("Cancel template selection")
        }
        .padding(24)
        .frame(width: 420)
        .background(SaneGradientBackground())
    }
}

struct TemplateRow: View {
    let template: ProfileTemplate
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: iconForTemplate)
                    .font(.title2)
                    .foregroundStyle(colorForTemplate)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                    Text(template.description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                }

                Spacer()

                Text("\(template.entries.count.formatted(.number.notation(.compactName))) entries")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Create from \(template.name) template")
        .accessibilityHint("\(template.description), \(template.entries.count) entries")
    }

    private var iconForTemplate: String {
        switch template {
        case .adBlocking: SaneIcons.templateAdBlock
        case .development: SaneIcons.templateDev
        case .social: SaneIcons.templateSocial
        case .privacy: SaneIcons.templatePrivacy
        }
    }

    private var colorForTemplate: Color {
        template.colorTag.uiColor
    }
}
