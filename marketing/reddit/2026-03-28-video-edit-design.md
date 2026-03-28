# Reddit Video Edit Design

**Date:** 2026-03-28  
**Channel:** Reddit (`r/macapps`)  
**Primary Asset:** `docs/assets/videos/1.mp4`

## Goal

Improve the launch video for Reddit so a first-time viewer understands the core idea within the first 2 seconds:

- one shortcut maps to one group of apps
- different shortcuts switch different contexts

The revised video should feel like a real native-product demo, not a polished ad.

## Audience

Cold viewers in `r/macapps` who are:

- technical
- fast-scanning
- skeptical of overly polished self-promo

The video must explain itself quickly without requiring the post title or comment for context.

## Constraints

- Prefer an **edit-only** pass using the existing `docs/assets/videos/1.mp4` footage.
- Do **not** recapture the full video unless the edit-only version still feels unclear.
- Keep the video short: target about **14-16 seconds**.
- Use minimal captions and hard cuts.
- Preserve the native, authentic feeling of the current footage.

## Approved Concept

Use the existing footage plus a generated intro card to show two shortcut-driven contexts:

- `Option+1 = Daily`
- `Option+3 = Chats`

The `Daily` group corresponds to the existing setup:

- Weather
- Stocks
- News
- TV

`Chats` remains the second context shown in the existing clip.

## Story Structure

### Beat 1: Intro card

Start with a generated intro card for about 1 second showing:

- `⌥1 Daily`
- `⌥3 Chats`

Use only the shortcut and group names.

Do not list member apps here.
Do not mention MRU / "last active app" here.

### Beat 2: First context

Cut from the intro card into the `Option+1` footage without adding a floating label.

Keep the strongest part of the current `Option+1` sequence and trim redundant cycling.

Prefer visual emphasis on:

- Weather
- Stocks
- News

Let TV appear, but do not make it the longest or most prominent app in the sequence.

### Beat 3: Second context

Cut to the first clear `Option+3` moment in the existing footage without adding a floating label.

This beat is important because it proves that different shortcuts map to different groups.

### Beat 4: Extra proof

End on the cleanest existing proof beat from the current footage:

- either the best HUD-visible return to `Option+1`
- or the cleanest hold/peek moment

Do not add a trailing overlay. Let the footage speak for itself.

## Editing Plan

1. Start from the existing first `Option+1` desktop beat in `1.mp4`.
2. Prepend a generated intro card showing `⌥1 Daily` and `⌥3 Chats`.
3. Cut out redundant repetition in the `Option+1` cycle.
4. Cut to the first strong `Option+3` chat sequence.
5. End on the best existing HUD/peek moment.
6. Keep total runtime roughly `15-16s`.

## Caption Style

Captions should be:

- short
- quiet
- consistent
- placed in one corner

Do not add:

- long explanation sentences
- pricing
- branding slogans
- feature laundry lists

## Why Edit-Only First

The existing `1.mp4` footage already contains the important proof points:

- a clear `Option+1` sequence
- a clear `Option+3` jump
- a later `Option+1` return with visible HUD

Because of that, the first attempt should be a pure re-edit of the existing file.

## Fallback If Edit-Only Is Still Too Cryptic

If the revised edit is still not clear enough, the smallest acceptable recapture is:

- a **very short settings shot** showing
  - `Daily -> Option+1`
  - `Chats -> Option+3`

This fallback should be added only if the edit-only version fails the cold-viewer test.

## Acceptance Criteria

The edit is successful if a cold viewer can infer all of the following quickly:

- shortcuts are assigned per group
- `Option+1` and `Option+3` represent different contexts
- the product switches through grouped apps instead of a giant global list
- the app feels native and fast

## Next Step

After review, create an implementation plan for the actual video re-edit using the approved structure above.
