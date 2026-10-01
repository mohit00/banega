# Matching engine (`app.engine`)

Pure Python, no I/O, fully typed. The API builds `RecipeView` / `EaterView` from the ORM
(`app/services/catalogue.py`) and calls:

| Function | Returns |
|---|---|
| `fit(eater, recipe)` | `Fit(status: fit\|tweak\|no, reason_key, reason_params)` |
| `summarize(eaters, recipe)` | `Summary(can, perfect, like, fits, badge, label_key/params, note_key/params)` |
| `score(summary, recipe, ctx, weights, eaters)` | `float` (F-6-05) |
| `rank(recipes, eaters, ctx, slot)` | `Ranking(pick, tiles[≤8])` with the variety rule (F-5.3-02) |
| `constraint_line(eaters, show_health=False)` | `([Constraint(key, params)], more)` (F-5.3-03) |

The engine returns **keys only**. The app turns them into strings (Hinglish / English / Hindi).

## `fit` rule order (first match wins)

The status of every seed recipe for the prototype household equals
`design/prototype_logic.js` (`tests/test_engine.py::test_prototype_parity_all_22`). Hard No's
follow F-6-03 so the reason names the real problem: chicken curry gives a Jain member
`non_veg`, not `onion_garlic`. The status is the same in either order.

| # | Status | `reason_key` | Condition | `reason_params` | Flutter `FitReason` | Copy (Hinglish) |
|---|---|---|---|---|---|---|
| 1 | no | `allergen` | eater allergen ∈ recipe allergens (derived) | `allergen`, `allergens` | *(new)* | "Isme {allergen} hai" |
| 2 | no | `non_veg` | veg / jain / no-onion-garlic / eggetarian vs meat or fish; pescatarian vs meat that is not fish | `meat` (pescatarian only) | `nonveg` | "Non-veg hai" |
| 3 | no | `has_egg` | veg / jain / no-onion-garlic vs egg | | `egg` | "Isme anda hai" |
| 4 | no | `beef` / `pork` / `not_halal` | non-veg exclusions (`no_beef`, `no_pork`, `halal_only`: pork or unknown meat) | | *(new)* | "Beef hai" / "Pork hai" / "Halal nahi" |
| 5 | no | `onion_garlic` | Jain and recipe has onion/garlic; or No-onion-garlic diet and recipe has onion/garlic | | `onionGarlic` | "Pyaaz-lahsun hai" |
| 5 | no | `root_veg` | Jain and recipe has a root vegetable (aloo, adrak, gajar ...) | | *(new)* | "Aloo / zameen-kand hai" |
| 5 | no | `not_jain_safe` | Jain and honey, mushroom or yeast-fermented item | | *(new)* | "Jain ke liye nahi" |
| 6 | no | `dairy` | eater `no_dairy` and recipe not dairy-free | | *(new)* | "Isme doodh / dahi hai" |
| 7 | no | `maida` | need "No maida" and tag `maida` | | `maida` | "Maida hai" |
| 8 | no | `dislike_main` | a disliked ingredient is the recipe's main (`is_main`) | `ingredient` (id or slug) | *(new)* | "Unko {x} pasand nahi" |
| 9 | no | `vrat` | eater has vrat today and recipe not `vrat_ok` | | *(new)* | "Aaj vrat hai" |
| 10 | tweak | `less_chilli_katori` | spice Kam and recipe spice 3 | | `lessChilli` | "Unki katori mein kam mirch" |
| 11 | tweak | `add_chilli` | spice Teekha and recipe spice 1 | | `extraChilli` | "Upar se laal mirch / achaar" |
| 12 | tweak | `small_portion_salad` | need Low sugar and no `lowSugar` tag | | `lowSugar` | "Portion chhota, salad zyada" |
| 13 | tweak | `less_oil` | need Low oil and no `lowOil` tag | | `lowOil` | "Kam tel mein banao" |
| 14 | tweak | `add_dahi_paneer` | need High protein and no `protein` tag | | `protein` | "Saath mein dahi/paneer" |
| 15 | tweak | `kid_separate_mild` | need Kid-friendly, no `kid` tag, spice > 1 | | `kid` | "Bachche ke liye alag, halka" |
| 16 | tweak | `dislike_skip` | a disliked ingredient is not the main one | `ingredient` | *(new)* | "Unki katori mein {x} mat daalo" |
| 17 | fit | `favourite_cuisine` | recipe cuisine ∈ eater cuisines | | `favCuisine` | "Favourite cuisine bhi" |
| 17 | fit | `perfect` | otherwise | | `perfect` | "Bilkul sahi" |

The Flutter enum today (`app/lib/core/engine/fit_engine.dart`) has the prototype's 12 keys in
camelCase; the rows marked *(new)* need labels there when the app switches to the backend
engine.

Tweaks keep the prototype's "not tagged" semantics (Low sugar without `lowSugar` is a Tweak).
F-6-01 proposes contra-tags (`sweet`, `fried`) instead; that is a content decision and a
one-line change per rule here.

## `summarize` keys

| `badge` | `label_key` | `label_params` | Prototype label |
|---|---|---|---|
| `fit` | `all_perfect` | | "Sabke liye perfect" |
| `tweak` | `all_with_tweaks` | `n` (number of tweaks) | "Sabke liye · {n} tweak" |
| `no` | `some` | `can`, `n` | "{can}/{n} ke liye" |
| `no` | `no_eaters` | | (nobody selected) |

`note_key`: `not_for` (`names`, `eater_ids`) → "{names} ke liye nahi"; `tweak_for` (`name`,
`eater_id`, `reason_key`, `reason_params`) → "{name}: {reason}"; `all_happy` → "Sab khush,
koi badlaav nahi".

## Score (F-6-05)

```
Score(r) = Σ over eaters e that can eat r [ 10 + 3·fit + 2·fav + 2·need_bonus + L(e,r) ]
           − 15·anyNo − Rep(r) + Stock(r)
```

- `need_bonus`: needs the recipe satisfies (low sugar ↔ `lowSugar`, low oil ↔ `lowOil`,
  high protein ↔ `protein`, kid-friendly ↔ `kid`).
- `L`: +4 if the eater's average rating is ≥ 4, −8 if ≤ 2 (the caller passes the windowed
  averages: 90 days for likes, 30 days for dislikes).
- `Rep`: 25 if the recipe was served within 3 days.
- `Stock`: +3 if every tracked ingredient is in stock, −5 per tracked ingredient that is Out;
  0 when stock is unknown.
- Ties: shorter `mins`, then recipe id. All weights live in `Weights`.

Ratings, served history and stock have no tables yet (Phases 5-7); `/v1/recommendations`
passes an empty `ScoreContext`, so those terms are 0 today.

## Rank

Recipes for the slot are scored and sorted. The top one is the pick; the grid holds the next
8, at most 2 per `dish_category`, never the pick. If the slot's catalogue is too small to
fill 8 under that rule, the remaining places are filled in rank order.

## Constraint line (F-5.3-03)

Priority: `allergy` (`name`, `allergen`) > `jain` / `no_onion_garlic` (`name`) > `veg` /
`eggetarian` (`names`; only when someone at the table eats egg or meat) > `vrat` (`name`) >
`kam_mirch` (`name`; kid with Kam spice, from the prototype) > health needs (`low_oil`,
`low_sugar`, ... ; only with `show_health=True`, F-5.3-05). Max 3 items plus a `more` count.
