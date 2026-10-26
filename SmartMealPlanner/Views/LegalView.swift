//
//  LegalView.swift
//  SmartMealPlanner
//
//  The privacy policy, terms of use and data sources with their licences, from the Markdown files in Legal/ (bundled,
//  so they show offline; the same files are linked from the README on GitHub).
//

import SwiftUI

enum LegalDocument: String, CaseIterable, Identifiable {
    case privacy = "PRIVACY"
    case terms = "TERMS"
    case credits = "CREDITS"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacy: "Privacy policy"
        case .terms: "Terms of use"
        case .credits: "Data sources and licences"
        }
    }

    var icon: String {
        switch self {
        case .privacy: "hand.raised.fill"
        case .terms: "doc.text.fill"
        case .credits: "books.vertical.fill"
        }
    }

    /// The document's Markdown, from the app bundle.
    var markdown: String {
        Bundle.main.url(forResource: rawValue, withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    /// Blocks to show: headings, list items and paragraphs (lines of a paragraph joined).
    static func blocks(_ markdown: String) -> [(kind: BlockKind, text: String)] {
        var blocks: [(BlockKind, String)] = []
        var paragraph: [String] = []
        func flush() {
            if !paragraph.isEmpty { blocks.append((.paragraph, paragraph.joined(separator: " "))) }
            paragraph = []
        }
        for raw in markdown.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("# ") {
                flush()  // the title is the screen's title
            } else if line.hasPrefix("## ") {
                flush()
                blocks.append((.heading, String(line.dropFirst(3))))
            } else if line.hasPrefix("- ") {
                flush()
                blocks.append((.item, String(line.dropFirst(2))))
            } else if let last = blocks.last, last.0 == .item, paragraph.isEmpty, raw.hasPrefix("  ") {
                blocks[blocks.count - 1].1 += " " + line  // a list item continued on the next line
            } else {
                paragraph.append(line)
            }
        }
        flush()
        return blocks
    }

    enum BlockKind { case heading, item, paragraph }
}

struct LegalView: View {
    let document: LegalDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(LegalDocument.blocks(document.markdown).enumerated()), id: \.offset) { _, block in
                    switch block.kind {
                    case .heading:
                        Text(block.text)
                            .font(.headline)
                            .foregroundStyle(Color.textPrimary)
                            .padding(.top, 8)
                    case .item:
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•")
                            Text(Self.inline(block.text))
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.textSecondary)
                    case .paragraph:
                        Text(Self.inline(block.text))
                            .font(.subheadline)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .tint(Color.brandPrimaryDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .screenBackground()
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("legal.\(document.rawValue.lowercased())")
    }

    /// Bold and links in a line of Markdown.
    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

/// The Legal card in Settings: links to the three documents.
struct LegalCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(icon: "checkmark.shield.fill", tint: .brandPrimary, tintBackground: .brandPrimarySoft,
                       title: "Privacy and legal", subtitle: "Your data stays on this phone")
                .padding(.bottom, 8)
            ForEach(LegalDocument.allCases) { document in
                if document != LegalDocument.allCases.first { RowDivider() }
                NavigationLink {
                    LegalView(document: document)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: document.icon)
                            .foregroundStyle(Color.brandPrimary)
                            .frame(width: 22)
                        Text(document.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.legal.\(document.rawValue.lowercased())")
            }
        }
        .card()
    }
}
