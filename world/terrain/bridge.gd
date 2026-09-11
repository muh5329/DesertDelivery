class_name Bridge
extends RefCounted
## One elevated stretch of Road: the strait crossing, the badlands viaduct, the aqueducts.
##
## The heightfield build finds the span that is actually above water or on arches, but the deck
## the courier rides over is longer than that — it runs out along the earth ramps on both banks.
## Working out where the real deck begins and ends used to be the caller's job, and both callers
## did it the same way, with the same three numbers copied: the aqueude builder in Island and
## the pedestrian router in RoadNavigation. Now the Bridge answers it.
##
## Interface:
##   samples                       the Road's world-space samples this bridge belongs to
##   from / to                     the raised span, as indices into `samples`
##   deck                          the deck height (m)
##   deck_span(ground) -> Vector2i first and last sample of the rideable deck, ramps included

## How far above the ground a sample must sit to still count as deck rather than road.
const RAMP_RISE := 0.25
## The longest ramp we will walk back along, in samples (~1 m each).
const RAMP_MAX := 80
## A few samples of margin so the deck geometry overlaps the bank it lands on.
const RAMP_MARGIN := 3

var road: int = 0
var samples := PackedVector3Array()
var from: int = 0
var to: int = 0
var deck: float = 0.0


func _init(p_road: int, p_samples: PackedVector3Array, p_from: int, p_to: int, p_deck: float) -> void:
	road = p_road
	samples = p_samples
	from = p_from
	to = p_to
	deck = p_deck


func length_in_samples() -> int:
	return to - from


## First and last sample of the deck the courier actually rides, walking out along the earth
## ramps on both banks until the road meets the ground again.
func deck_span(ground) -> Vector2i:
	var first := from
	while first > 0 and from - first < RAMP_MAX \
			and samples[first - 1].y - ground.height_at(samples[first - 1].x, samples[first - 1].z) > RAMP_RISE:
		first -= 1
	var last := to
	while last < samples.size() - 1 and last - to < RAMP_MAX \
			and samples[last + 1].y - ground.height_at(samples[last + 1].x, samples[last + 1].z) > RAMP_RISE:
		last += 1
	return Vector2i(maxi(first - RAMP_MARGIN, 0), mini(last + RAMP_MARGIN, samples.size() - 1))
