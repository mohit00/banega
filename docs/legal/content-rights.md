# Banega Recipe and Photo Rights

> **DRAFT — must be reviewed by a qualified Indian lawyer before publishing.**
> Internal checklist and template for the 1,000-recipe catalogue (recipe text in English, Hinglish and Hindi; optional `image_url` and `video_url` per recipe in `backend/app/models/catalogue.py`).

> **Short mein (Hinglish summary)**
> Recipe ka idea (ingredients ki list) copyright nahi hota, lekin kisi aur ki likhi hui recipe ka text aur photo hota hai. Isliye: recipe text apne shabdon mein likho, translation bhi apni ho, photo khud khinchwao (assignment ke saath) ya licence lo. YouTube video sirf link ke roop mein — thumbnail ya video app mein copy nahi.

---

## 1. What is protected, in short

- Under the Copyright Act, 1957, a list of ingredients and a basic method are generally ideas/facts and are hard to protect. The **expression** — the way the steps, tips and story are written — and every **photo** and **video** are protected. A **translation** of someone else's text is a derivative work that needs their permission.
- FRD finding F-7-06 flagged the "curated from public sources" approach as a licensing risk. The safest position for v1: all catalogue text is **original** (written by Kornea or a contributor who assigns rights), and all media is **owned or licensed**.

## 2. Recipe text checklist (per recipe or per batch)

- [ ] Steps, tips and descriptions are written fresh in our own words; not copied or closely paraphrased from a cookbook, blog, app or video transcript.
- [ ] If an AI tool helped draft text, a person reviewed and edited it, and the prompt did not paste in third-party recipes. Keep a note of which recipes were AI-assisted.
- [ ] Translations (Hinglish, Hindi) were made by Kornea staff, a contributor who assigned rights, or machine translation of **our own** English text followed by native review.
- [ ] Dish names and traditional recipes are used generically; no brand names presented as ours (e.g. no "Haldiram's-style" in a title).
- [ ] Health-like tags (low sugar, high protein, kid-friendly …) are descriptive only, with no medical claims (matches the Maharaj post-validator's banned phrases).
- [ ] Allergen and diet flags are derived from ingredient data and spot-checked by a person.
- [ ] The contributor (if any) signed the assignment in section 5, and the recipe record notes who wrote it.

`[Note: the catalogue has no "source / author / licence" field today. Recommend adding provenance columns (author, licence type, assignment reference, AI-assisted yes/no) or keeping a spreadsheet keyed by recipe slug.]`

## 3. Photos checklist

Allowed:

- [ ] **Commissioned** photos with a written **assignment** of copyright to Kornea (section 5), or
- [ ] **Licensed** stock photos where the licence covers use in a commercial mobile app and app-store marketing, for the life of the app, worldwide. Save the licence and the invoice.
- [ ] Our own photos taken by Kornea staff in the course of employment (confirm the employment contract assigns IP).

Not allowed:

- ✗ Photos copied from Google Images, blogs, Instagram, Pinterest or recipe sites, even with credit.
- ✗ "Free" images without a licence that clearly allows commercial app use.
- ✗ Photos with identifiable people (or children) without a signed model release.
- ✗ Photos showing third-party brands or packaging prominently.

For each photo, record: file name, recipe slug, photographer, date, licence/assignment reference.

## 4. Videos and YouTube

- [ ] `video_url` is stored and shown **only as a link** that opens YouTube (or another site) in its own app or browser. Banega does not copy, download or re-host videos.
- [ ] Do **not** show YouTube **thumbnails** inside Banega unless we have a licence from the creator, or we use YouTube's official embedded player under the YouTube API Services Terms (which brings its own policy obligations). — https://developers.google.com/youtube/terms/api-services-terms-of-service
- [ ] Prefer linking to the creator's own channel; do not link to re-uploads.
- [ ] Remove a link promptly if the creator asks.
- [ ] If we commission our own videos, use the assignment template in section 5.

## 5. Template — Content Contributor and Photographer Assignment

> Plain-English template. Adapt with the lawyer; stamp duty may apply depending on the state where it is signed.

---

**CONTENT ASSIGNMENT AGREEMENT**

This agreement is made on `[DATE]` at `[PLACE]` between:

**`[KORNEA LEGAL ENTITY NAME]`**, `[REGISTERED ADDRESS]` ("Kornea"); and

**`[CONTRIBUTOR NAME]`**, `[ADDRESS]`, PAN `[PAN]` ("Contributor").

**1. Work.** The Contributor will create the following for the Banega app: `[e.g. 50 recipe texts in English and Hindi / photos of 40 dishes listed in Schedule A / recipe videos]` (the "Work"), delivered by `[DATE]` in `[format, e.g. JPEG 3000 px, RAW files; DOCX]`.

**2. Fee.** Kornea will pay `[₹ AMOUNT]` (`[plus GST if applicable]`) within `[15]` days of accepted delivery. The fee covers the assignment below; no royalty is payable.

**3. Assignment of copyright.** Under section 18 and 19 of the Copyright Act, 1957, the Contributor assigns to Kornea all copyright in the Work, including all rights to reproduce, adapt, translate, edit, crop, publish and communicate it to the public, in all media now known or later developed, **worldwide**, for the **full term of copyright**. `[Note: section 19(5)-(6) — if duration or territory is not stated, the assignment defaults to 5 years and India only. Keep "worldwide" and "full term" explicit.]`

**4. Moral rights.** The Contributor agrees that Kornea may edit, crop, translate and adapt the Work, and may publish it with or without credit. `[Credit preference: "Photo: [name]" in the app's About screen / none.]`

**5. Originality.** The Contributor confirms that the Work is their own original work; it does not copy anyone else's text, photos or videos; it does not infringe anyone's rights; and any people, children or private places shown have given written permission (model / property releases attached).

**6. AI tools.** The Contributor will tell Kornea in writing if any part of the Work was generated with an AI tool, and will not paste third-party content into such tools.

**7. Food styling and brands.** No third-party brand names, logos or packaging will be prominent in photos or videos unless Kornea agrees in writing.

**8. Portfolio.** The Contributor may show the Work in their personal portfolio after Banega has published it, with a credit to Banega, but may not license it to anyone else.

**9. Indemnity.** The Contributor will compensate Kornea for losses caused by a breach of clause 5.

**10. Confidentiality.** The Contributor will keep unreleased recipes and app information confidential.

**11. Law.** This agreement is governed by the laws of India. Courts at `[JURISDICTION CITY]` have jurisdiction.

| For Kornea | Contributor |
|---|---|
| Name: `[ ]` | Name: `[ ]` |
| Signature: | Signature: |
| Date: | Date: |

**Schedule A — Work list:** `[recipe slugs / photo list]`

---
