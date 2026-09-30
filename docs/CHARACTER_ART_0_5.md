# Character art direction — 0.5

The current characters are procedural skinned meshes in `scripts/character_model.gd`. They animate and
perform well, but their blocky shoulder shapes, feature-light faces and oversized hats still read as
cartoon characters in the night-time lineup. The user wants grounded people within the late-1990s/early-2000s
crime-city style. A small 0.5 pass lowered the head, softened the painted facial marks, removed the separate
ball-shaped nose tip, and reduced hat brims and crowns. This improves the close-up silhouette; it does not
finish the character-art goal.

Keep Godot for this pass. The screenshot problem comes from the current meshes, textures, materials and
animation poses, not an engine limitation shown by the prototype. Moving engines would not replace those
assets and would interrupt the working vehicle, input and combat systems.

For the next art pass, build or source one legally usable, proportionate human base mesh and adapt its rig to
the existing `CharacterModel.build`, `animate`, `seated` and `riding` interface. Use a restrained face atlas,
clothing folds and materials that respond to street lighting. Crew recognition should come from wardrobe,
colour accents and silhouette details rather than giant hats or exaggerated facial marks. Keep the four
outfits in one visual era. Make seated shoulders, wrists and head positions credible from the new first-person
car camera and from another player's window view.

Acceptance captures: each crew from front, side and three-quarter angles at daylight and dusk; idle, walking,
aiming, seated in sedan/SUV and on motorcycle. Review at close range and typical street distance. Faces
should look human at close range and crews remain distinguishable at street distance. Check draw calls and
memory after importing authored art before deciding on further detail or an engine change.
