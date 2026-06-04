---
name: comic-epub-splitter
description: Build EPUB files from comic image folders, especially manga/manhua scans where landscape JPGs are two-page spreads or source images are too large for ebook readers. Use when the user asks to package JPG/JPEG comic pages into EPUB, split double-page landscape images into single pages, preserve right-to-left reading order, compress EPUB images below a size limit such as 1MB, or validate a local image-based EPUB.
---

# Comic EPUB Splitter

## Workflow

Use this skill for local comic folders made of JPG/JPEG page images.

1. Confirm the source folder and output EPUB path.
2. Sort input `.jpg` and `.jpeg` files by filename.
3. Treat landscape images (`width > height`) as two-page spreads.
4. Split each landscape image into two single-page images in this order:
   - right half first
   - left half second
5. Keep portrait images as single pages.
6. Before packaging, encode every EPUB image as JPG under the configured size limit.
7. Package one XHTML wrapper per image into an EPUB3 file.
8. Validate the result before reporting completion.

Default to excluding PNG files unless the user explicitly asks to include them.

## Script

Prefer running `scripts/build-comic-epub.ps1` instead of rewriting the EPUB creation logic.

Example:

```powershell
& "C:\Users\jchua\.codex\skills\comic-epub-splitter\scripts\build-comic-epub.ps1" `
  -SourceDir "D:\codex\comic\偷窺孔 第01集 全彩版" `
  -OutputEpub "D:\codex\comic\偷窺孔 第01集 全彩版.epub" `
  -Title "偷窺孔 第01集 全彩版"
```

The script overwrites the output EPUB if it already exists. It writes a temporary build directory next to the output, then removes it after packaging.

## Compression

Use these defaults unless the user says otherwise:

- `-MaxImageBytes 1000000`: every image embedded in the EPUB must be smaller than 1,000,000 bytes.
- `-MaxImageWidth 1800`: resize each single page to at most 1800px wide before JPEG encoding.
- JPEG quality attempts: start at 82, then step down; if still too large, reduce width and retry.

This compression applies after splitting spreads, so each EPUB page is a single compressed page image.

## Validation

After building, verify these facts and include them in the final response:

- `mimetype` is the first ZIP entry and equals `application/epub+zip`.
- `META-INF/container.xml`, `EPUB/package.opf`, `EPUB/nav.xhtml`, first page, and last page parse as XML.
- Image entry count equals page XHTML count.
- Wide image count inside the EPUB is `0` after split mode.
- Images over the configured byte limit count is `0`.
- Report source JPG count, split source count, single source count, EPUB page count, largest embedded image size, and final file size.

## Assumptions

Use these defaults unless the user says otherwise:

- Input format: `.jpg` and `.jpeg` only.
- Reading direction: right-to-left for split spreads.
- Split point: center of the image; if width is odd, the right half gets the extra pixel.
- Internal EPUB filenames: ASCII names such as `page0001.jpg` for reader compatibility.
- Compression target: less than 1,000,000 bytes per EPUB image, not merely less than or equal.
