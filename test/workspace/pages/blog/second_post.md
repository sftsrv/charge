---
title: Second Post
description: An example age with complex elements
date: 2026-02-17
tags:
  - special
  - blog
---

## Welcome!

This is some content in Markdown that can be rendered to your site[^1] [^2]

Here's a code block and some other _fancy_[^Footnote about formatting] formatting

<my-custom-tag data="hello world">

## Nested Heading

```gleam
code |> print_me |> echo

// The footnote parser should not detect this [^1] or [^footnote]
```

</my-custom-tag>

<my-async-tag data="hello world"></my-async-tag>

<my-custom-image src="../../static/images/special-1.jpg" />

### Some Images to Optimize

![My first image](../../static/images/image-1.jpg)

![My second image](../../static/images/image-2.jpg)


## Footnotes

- [^1]: Or someone else's site I guess
- [^2]: Or maybe just an RSS feed
- [^Footnote about formatting]: Or as fancy as you can get in Markdown I guess
