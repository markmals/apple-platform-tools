import Foundation
import TestSupport
import Testing

@testable import PatternIndex

// MARK: - Layer 1: tokenizer

@Suite(.spec("story.sdk-search.pattern-search"))
struct TokenizerTests {
  @Test func `lowercases and strips punctuation to a single token`() {
    // "NSGlassEffectView" -> single lowercased token; punctuation removed.
    #expect(Tokenizer.tokenize("NSGlassEffectView!!") == ["nsglasseffectview"])
  }

  @Test func `lowercases invariantly to avoid the Turkish dotless-i`() {
    // A capital I must fold to ASCII 'i', not the dotless 'ı', regardless of host locale.
    let out = Tokenizer.invariantLowercased("INSPECTOR")
    #expect(out == "inspector")
    #expect(out.contains("i"))
  }

  @Test func `drops single-char tokens and stopwords`() {
    // "a" is length-1 (dropped), "is" is a stopword (dropped); "glass" survives.
    #expect(Tokenizer.tokenize("a glass is here") == ["glass", "here"])
  }

  @Test func `preserves hyphens inside tokens`() {
    // The char class [^a-z0-9\s\-] preserves hyphens; they stay inside the token.
    #expect(Tokenizer.tokenize("drag-and-drop view") == ["drag-and-drop", "view"])
  }

  @Test func `strips non-alphanumerics to spaces then splits`() {
    // Slashes/dots become spaces; the resulting parts tokenize separately.
    #expect(Tokenizer.tokenize("NSView.cornerConfiguration") == ["nsview", "cornerconfiguration"])
  }

  @Test func `collapses consecutive separators with no empty tokens`() {
    // "effect" is in StopWords.common (ported verbatim), so it is filtered out;
    // the point here is that the run of spaces collapses (no empty tokens).
    #expect(Tokenizer.tokenize("glass    view") == ["glass", "view"])
  }

  @Test func `compacts a query by stripping all non-alphanumerics`() {
    #expect(Tokenizer.compactQuery("Color Picker Button") == "colorpickerbutton")
    #expect(Tokenizer.compactQuery("NSView.cornerConfiguration") == "nsviewcornerconfiguration")
  }

  @Test func `splits PascalCase into space-separated words`() {
    #expect(Tokenizer.splitCamelCase("NSGlassEffectView") == "NS Glass Effect View")
    #expect(Tokenizer.splitCamelCase("ColorPicker") == "Color Picker")
  }

  @Test func `tokenizes the camel-split form into its surviving parts`() {
    // "effect" is a stopword (verbatim from winui-search), so it drops out after
    // tokenizing the split form; the other PascalCase parts survive.
    let parts = Tokenizer.tokenize(Tokenizer.splitCamelCase("NSGlassEffectView"))
    #expect(parts == ["ns", "glass", "view"])
  }
}

// MARK: - Layer 1: synonym pipeline

@Suite(.spec("story.sdk-search.pattern-search"))
struct SynonymPipelineTests {
  @Test func `preprocess appends the merged phrase token and keeps the originals`() {
    // "split view" -> appends the merged AppKit token "nssplitviewcontroller";
    // original words remain searchable.
    let pre = Synonyms.preprocess("split view")
    let toks = Tokenizer.tokenize(pre)
    #expect(toks.contains("split"))
    #expect(toks.contains("view"))
    #expect(toks.contains("nssplitviewcontroller"))
  }

  @Test func `preprocess merges the glass-effect phrase`() {
    let toks = Tokenizer.tokenize(Synonyms.preprocess("glass effect"))
    #expect(toks.contains("nsglasseffectview"))
  }

  @Test func `preprocess stems inflected words`() {
    // "dragging" -> appends "drag" (doubled-consonant -ing stem).
    let toks = Tokenizer.tokenize(Synonyms.preprocess("dragging"))
    #expect(toks.contains("drag"))
  }

  @Test func `expand maps sidebar to the splitviewcontroller terms`() {
    // The headline AppKit retranslation: 'sidebar' -> splitviewcontroller family.
    let expanded = Synonyms.expand(["sidebar"])
    #expect(expanded.contains("sidebar"))
    #expect(expanded.contains("nssplitviewcontroller"))
  }

  @Test func `expand maps glass to NSGlassEffectView`() {
    #expect(Synonyms.expand(["glass"]).contains("nsglasseffectview"))
  }

  @Test func `expand maps table to both table and outline view`() {
    let e = Synonyms.expand(["table"])
    #expect(e.contains("nstableview"))
    #expect(e.contains("nsoutlineview"))
  }

  @Test func `expand maps modal to alert, sheet, and popover`() {
    let e = Synonyms.expand(["modal"])
    #expect(e.contains("nsalert"))
    #expect(e.contains("sheet"))
    #expect(e.contains("nspopover"))
  }

  @Test func `expand appends each synonym at most once`() {
    // Per the port: original tokens pass through unchanged (dupes not collapsed),
    // but an appended synonym is added at most once even when its trigger repeats.
    let e = Synonyms.expand(["glass", "glass"])
    #expect(e.filter { $0 == "nsglasseffectview" }.count == 1)
  }

  @Test func `expand suppresses a bare token's generics when a compound pins the intent`() {
    // When a longer compound ending in the bare token is present, the bare token's
    // generic synonyms are NOT appended (intent already pinned).
    let e = Synonyms.expand(["filepicker", "picker"])
    // 'picker' generic synonyms (e.g. nspopupbutton) must be suppressed.
    #expect(!e.contains("nspopupbutton"))
    // but the compound's own expansion is allowed.
    #expect(e.contains("filepicker"))
  }

  @Test func `expand does expand a bare token with no compound parent`() {
    // Control: bare 'picker' alone DOES expand.
    let e = Synonyms.expand(["picker"])
    #expect(e.contains("nspopupbutton") || e.contains("nsopenpanel"))
  }
}
