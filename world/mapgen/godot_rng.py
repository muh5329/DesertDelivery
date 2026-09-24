"""Godot 4's RandomNumberGenerator (PCG32, `RandomPCG`) in Python, so the generator can choose a
plot's seed by what the architecture kit will build from it (ArchStyles.plan draws its choices
from `RandomNumberGenerator.seed = plot.seed` in a fixed order). Checked against the kit by
tests/fw_seed_check.gd."""
M64 = (1 << 64) - 1
INC = 1442695040888963407


class PCG:
    def __init__(self, seed):
        self.inc = ((INC << 1) | 1) & M64
        self.state = 0
        self.next()
        self.state = (self.state + (seed & M64)) & M64
        self.next()

    def next(self):
        old = self.state
        self.state = (old * 6364136223846793005 + self.inc) & M64
        xs = (((old >> 18) ^ old) >> 27) & 0xFFFFFFFF
        rot = old >> 59
        return ((xs >> rot) | (xs << ((-rot) & 31))) & 0xFFFFFFFF

    def randf(self):
        # Godot 4 RandomPCG::randf: the exponent from one draw's leading zeros, 24 bits from the next
        proto = self.next()
        if proto == 0: return 0.0
        clz = 32 - proto.bit_length()
        m = (self.next() >> 8) | 0x1 | 0x800000
        return m * 2.0 ** (-24 - clz)

    def randf_range(self, a, b):
        return a + (b - a) * self.randf()

    def randi_range(self, a, b):
        bound = (b - a + 1) & 0xFFFFFFFF
        threshold = ((-bound) & 0xFFFFFFFF) % bound
        while True:
            r = self.next()
            if r >= threshold: return a + r % bound


def sarmada_wall(seed, floors):
    """The wall colour ArchStyles.plan picks for a Sarmada house or shop with this seed:
    ("white", i) = SARMADA_WALLS[i] (limewash), ("ochre", i) = SARMADA_OCHRE[i] (adobe)."""
    r = PCG(seed)
    r.randf_range(0.05, 0.7)                 # q.weather
    r.randi_range(0, 5)                      # q.paint (WOOD_PAINTS)
    r.randi_range(0, 3)                      # q.roof_tint (ROOF_TINTS)
    r.randi_range(0, 2)                      # q.chimneys
    for i in range(max(1, min(7, floors))): r.randf_range(-0.08, 0.08)   # _floors
    ochre = r.randf() < 0.3
    return ("ochre" if ochre else "white", r.randi_range(0, 3))
