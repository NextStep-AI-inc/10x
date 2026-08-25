import Foundation
import Testing
@testable import TenXApp

@Test(arguments: [
    ("Sources/App.swift", "swift", 0xF05138),
    ("web/client.ts", "typescript", 0x3178C6),
    ("web/Component.tsx", "react", 0x087EA4),
    ("web/client.js", "javascript", 0xF7DF1E),
    ("web/Component.jsx", "react", 0x087EA4),
    ("scripts/train.py", "python", 0x3776AB),
    ("src/lib.rs", "rust", 0x000000),
    ("cmd/server.go", "go", 0x00ADD8),
    ("src/Main.java", "openjdk", 0x437291),
    ("src/Main.kt", "kotlin", 0x7F52FF),
    ("src/main.c", "c", 0xA8B9CC),
    ("src/main.cpp", "cplusplus", 0x00599C),
    ("App/Delegate.m", "apple", 0x000000),
    ("App/Delegate.mm", "apple", 0x000000),
    ("src/Program.cs", "dotnet", 0x512BD4),
    ("app/models/user.rb", "ruby", 0xCC342D),
    ("public/index.php", "php", 0x777BB4),
    ("lib/main.dart", "dart", 0x0175C2),
    ("scripts/init.lua", "lua", 0x2C2D72),
    ("scripts/build.sh", "gnubash", 0x4EAA25),
    ("public/index.html", "html5", 0xE34F26),
    ("styles/main.css", "css", 0x663399),
    ("styles/main.scss", "sass", 0xCC6699),
    ("fixtures/data.json", "json", 0x000000),
    ("docs/README.md", "markdown", 0x000000),
    ("config/app.yml", "yaml", 0xCB171E),
    ("db/schema.sql", "postgresql", 0x4169E1),
    ("api/schema.graphql", "graphql", 0xE10098),
    ("web/App.vue", "vuedotjs", 0x4FC08D),
    ("web/App.svelte", "svelte", 0xFF3E00),
    ("web/Page.astro", "astro", 0xBC52EE),
])
func commonFileTypesUseTheirBrandMarks(
    path: String,
    assetName: String,
    colorHex: Int
) {
    let descriptor = FileTypeIconDescriptor.make(path: path)

    #expect(descriptor.assetName == assetName)
    #expect(descriptor.colorHex == colorHex)
}

@Test func unknownAndExtensionlessFilesUseTheNeutralFallback() {
    #expect(FileTypeIconDescriptor.make(path: "archive.xyz").assetName == nil)
    #expect(FileTypeIconDescriptor.make(path: "LICENSE").assetName == nil)
    #expect(FileTypeIconDescriptor.make(path: ".gitignore").assetName == nil)
}

@Test func everyBrandedFileTypeHasABundledVectorAsset() {
    for descriptor in FileTypeIconDescriptor.brandedDescriptors {
        #expect(Bundle.main.url(
            forResource: descriptor.assetName,
            withExtension: "svg",
            subdirectory: "FileTypeIcons") != nil)
    }
}
