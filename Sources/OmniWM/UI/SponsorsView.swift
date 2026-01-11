import AppKit
import SwiftUI

struct SponsorsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            headerSection

            HStack(spacing: 32) {
                SponsorCardView(
                    name: "Christopher2K",
                    githubUsername: "Christopher2K",
                    imageName: "christopher2k",
                    imageExtension: "jpg",
                    rank: .first
                )

                SponsorCardView(
                    name: "Aelte",
                    githubUsername: "aelte",
                    imageName: "aelte",
                    imageExtension: "png",
                    rank: .second
                )

                SponsorCardView(
                    name: "captainpryce",
                    githubUsername: "captainpryce",
                    imageName: "captainpryce",
                    imageExtension: "jpg",
                    rank: .third
                )
            }
            .padding(.horizontal, 24)

            Button(action: onClose) {
                Text("Close")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 100)
            }
            .buttonStyle(GlassButtonStyle())
            .padding(.top, 8)
        }
        .padding(32)
        .frame(width: 700, height: 380)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .scaleEffect(appeared ? 1.0 : 0.95)
        .opacity(appeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                appeared = true
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Text("Omni Sponsors")
                    .font(.system(size: 28, weight: .bold))
                Image(systemName: "sparkles")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.yellow, .orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            Text("Thank you to our amazing supporters!")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
    }
}

enum SponsorRank {
    case first
    case second
    case third

    var gradientColors: [Color] {
        switch self {
        case .first:
            return [Color(red: 1.0, green: 0.84, blue: 0.0),
                    Color(red: 1.0, green: 0.55, blue: 0.0)]
        case .second:
            return [Color(red: 0.91, green: 0.91, blue: 0.91),
                    Color(red: 0.66, green: 0.75, blue: 0.85)]
        case .third:
            return [Color(red: 0.82, green: 0.41, blue: 0.12),
                    Color(red: 0.42, green: 0.24, blue: 0.10)]
        }
    }

    var glowColor: Color {
        switch self {
        case .first:
            return Color(red: 1.0, green: 0.7, blue: 0.0)
        case .second:
            return Color(red: 0.6, green: 0.7, blue: 0.85)
        case .third:
            return Color(red: 0.75, green: 0.38, blue: 0.12)
        }
    }

    var label: String {
        switch self {
        case .first:
            return "1st"
        case .second:
            return "2nd"
        case .third:
            return "3rd"
        }
    }
}

struct SponsorCardView: View {
    let name: String
    let githubUsername: String
    let imageName: String
    let imageExtension: String
    let rank: SponsorRank

    @State private var isHovered = false

    private var githubURL: URL? {
        URL(string: "https://github.com/\(githubUsername)")
    }

    var body: some View {
        Button(action: {
            if let url = githubURL {
                NSWorkspace.shared.open(url)
            }
        }) {
            VStack(spacing: 16) {
                GlowingAvatarView(
                    imageName: imageName,
                    imageExtension: imageExtension,
                    rank: rank
                )

                VStack(spacing: 4) {
                    Text(name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Image(systemName: "link")
                            .font(.system(size: 11))
                        Text("@\(githubUsername)")
                            .font(.system(size: 13))
                    }
                    .foregroundStyle(.secondary)
                }

                Text(rank.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: rank.gradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: rank.glowColor.opacity(isHovered ? 0.3 : 0.1), radius: isHovered ? 12 : 6)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct GlowingAvatarView: View {
    let imageName: String
    let imageExtension: String
    let rank: SponsorRank

    @State private var isAnimating = false

    private var avatarImage: NSImage? {
        guard let url = Bundle.module.url(forResource: imageName, withExtension: imageExtension),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        return image
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: rank.gradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 4
                )
                .frame(width: 88, height: 88)
                .shadow(
                    color: rank.glowColor.opacity(isAnimating ? 0.8 : 0.5),
                    radius: isAnimating ? 12 : 8
                )

            if let image = avatarImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(.quaternary)
                    .frame(width: 76, height: 76)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}
