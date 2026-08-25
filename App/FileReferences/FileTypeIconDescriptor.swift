import Foundation

struct FileTypeIconDescriptor: Equatable, Hashable, Sendable {
    let assetName: String?
    let colorHex: Int

    static let fallback = FileTypeIconDescriptor(
        assetName: nil,
        colorHex: TenXPalette.mutedTextHex)

    static let brandedDescriptors = Array(Set(byExtension.values)).sorted {
        ($0.assetName ?? "") < ($1.assetName ?? "")
    }

    static func make(path: String) -> FileTypeIconDescriptor {
        let fileExtension = URL(filePath: path).pathExtension.lowercased()
        return byExtension[fileExtension] ?? fallback
    }

    private static let byExtension: [String: FileTypeIconDescriptor] = {
        var result: [String: FileTypeIconDescriptor] = [:]

        func register(_ extensions: [String], asset: String, color: Int) {
            let descriptor = FileTypeIconDescriptor(assetName: asset, colorHex: color)
            for fileExtension in extensions {
                result[fileExtension] = descriptor
            }
        }

        register(["swift"], asset: "swift", color: 0xF05138)
        register(["ts"], asset: "typescript", color: 0x3178C6)
        register(["tsx", "jsx"], asset: "react", color: 0x087EA4)
        register(["js", "mjs", "cjs"], asset: "javascript", color: 0xF7DF1E)
        register(["py", "pyw"], asset: "python", color: 0x3776AB)
        register(["rs"], asset: "rust", color: 0x000000)
        register(["go"], asset: "go", color: 0x00ADD8)
        register(["java"], asset: "openjdk", color: 0x437291)
        register(["kt", "kts"], asset: "kotlin", color: 0x7F52FF)
        register(["c", "h"], asset: "c", color: 0xA8B9CC)
        register(["cc", "cpp", "cxx", "hpp"], asset: "cplusplus", color: 0x00599C)
        register(["m", "mm"], asset: "apple", color: 0x000000)
        register(["cs"], asset: "dotnet", color: 0x512BD4)
        register(["rb"], asset: "ruby", color: 0xCC342D)
        register(["php"], asset: "php", color: 0x777BB4)
        register(["dart"], asset: "dart", color: 0x0175C2)
        register(["lua"], asset: "lua", color: 0x2C2D72)
        register(["bash", "sh", "zsh"], asset: "gnubash", color: 0x4EAA25)
        register(["htm", "html"], asset: "html5", color: 0xE34F26)
        register(["css"], asset: "css", color: 0x663399)
        register(["sass", "scss"], asset: "sass", color: 0xCC6699)
        register(["json", "jsonc"], asset: "json", color: 0x000000)
        register(["md", "mdx", "markdown"], asset: "markdown", color: 0x000000)
        register(["yaml", "yml"], asset: "yaml", color: 0xCB171E)
        register(["sql"], asset: "postgresql", color: 0x4169E1)
        register(["gql", "graphql"], asset: "graphql", color: 0xE10098)
        register(["vue"], asset: "vuedotjs", color: 0x4FC08D)
        register(["svelte"], asset: "svelte", color: 0xFF3E00)
        register(["astro"], asset: "astro", color: 0xBC52EE)

        return result
    }()
}
