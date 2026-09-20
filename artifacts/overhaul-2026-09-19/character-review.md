# Resident wardrobe review

All 64 resident records now instantiate deterministic identity and occupation wardrobe variants on the shared animated courier rig. Added flared folded apron geometry, work caps, baker toques, broad straw hats, fisher knit caps, spectacles, satchels, hair buns/braids/curls, and subtle torso/head proportions. Palette data still controls skin, hair and clothing. Body pivots and right-hand prop attachment remain intact; no separate collision bodies are added.

Actual Godot runtime images:
- resident-lineup.png: teacher, shepherd, shopkeeper, mechanic, baker, gardener (left to right).
- resident-lineup-second.png: stonemason, ranger, fisher, courier and produce driver (left to right).

Iteration: first capture faced away and was too small to judge, as the independent controls critic pointed out. Reversed camera, enlarged framing and separated rows. Front render exposed back-face culling of apron panels; reversed winding. Independent front-view review then flagged crown hair breaking through caps; enlarged and raised crowns and recaptured, resolving visible breakthrough. Identity reassignment restores head scale from the original imported scale, avoiding cumulative growth.

Validation: life_tests passed with zero failures after wardrobe changes, including grounded boots, driving/standing transitions, and vehicle/player collisions. Images use real runtime geometry, not concept art.

Limitations: these are authored procedural wardrobe/accessory variants with a shared base face and rig, not 64 unique bespoke meshes. Aprons are rigid panels without cloth simulation; the original courier scarf and suspenders remain part of the shared base asset. Not AAA signoff.
