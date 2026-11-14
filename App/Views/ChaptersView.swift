import SwiftUI

/// Table of contents.
struct ChaptersView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    if let book = player.book {
                        Section {
                            ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                                Button {
                                    player.jumpToChapter(index)
                                    dismiss()
                                } label: {
                                    row(index: index, chapter: chapter)
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        } header: {
                            Text(book.chapterSource.summary)
                        } footer: {
                            Text("Total length \(TimeFormat.short(book.duration))")
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo(player.currentChapterIndex, anchor: .center)
                }
            }
            .navigationTitle("Contents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(index: Int, chapter: Chapter) -> some View {
        let isCurrent = index == player.currentChapterIndex
        let isPast = index < player.currentChapterIndex
        return HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: player.isPlaying ? "speaker.wave.2.fill" : "speaker.fill")
                        .foregroundStyle(.tint)
                } else {
                    Text("\(index + 1)")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(chapter.title)
                    .font(isCurrent ? .body.weight(.semibold) : .body)
                    .foregroundStyle(isPast ? .secondary : .primary)
                    .lineLimit(2)
                if isCurrent {
                    ProgressView(value: chapter.duration > 0 ? (player.currentTime - chapter.start) / chapter.duration : 0)
                        .tint(.orange)
                }
            }

            Spacer()

            Text(TimeFormat.clock(chapter.duration / (settings.adjustForSpeed ? player.speed : 1)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
