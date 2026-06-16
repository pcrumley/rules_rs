"""Unit tests for triple -> constraint-set projection.

The core guarantee is that every supported triple projects to a *unique*
constraint set: that is exactly what makes the generated toolchain `select`s
(keyed on per-triple config_settings) unambiguous, so any supported triple is
buildable.
"""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load(
    ":triples.bzl",
    "ALL_TARGET_TRIPLES",
    "triple_to_rust_constraint_set",
)

_DISAMBIGUATOR_CONSTRAINTS = [
    "@rules_rs//rs/platforms/constraints:hardfloat",
    "@rules_rs//rs/platforms/constraints:softfloat",
    "@rules_rs//rs/platforms/constraints:wasm_threads_on",
    "@rules_rs//rs/platforms/constraints:wasm_threads_off",
]

# Triples that have no colliding sibling and so must NOT gain a disambiguator:
# bare/lone thumb and android eabi targets, a lone netbsd eabihf target, and a
# representative non-ARM triple. thumbv7em-none-{eabi,eabihf} are included
# because rules_rust already maps them to distinct CPUs (armv7e-m vs armv7e-mf),
# so they do not collide and tagging them would break non-annotated consumers.
_LONE_TRIPLES = [
    "thumbv6m-none-eabi",
    "thumbv7m-none-eabi",
    "thumbv7em-none-eabi",
    "thumbv7em-none-eabihf",
    "arm-linux-androideabi",
    "armv7-linux-androideabi",
    "armv7-unknown-netbsd-eabihf",
    "x86_64-unknown-linux-gnu",
]

# Genuinely colliding soft/hard (and threads on/off) pairs that the
# disambiguation must separate.
_PAIRS = [
    ("arm-unknown-linux-gnueabi", "arm-unknown-linux-gnueabihf"),
    ("arm-unknown-linux-musleabi", "arm-unknown-linux-musleabihf"),
    ("armv7-unknown-linux-gnueabi", "armv7-unknown-linux-gnueabihf"),
    ("armv7-unknown-linux-musleabi", "armv7-unknown-linux-musleabihf"),
    ("thumbv8m.main-none-eabi", "thumbv8m.main-none-eabihf"),
    ("aarch64-unknown-none", "aarch64-unknown-none-softfloat"),
    ("wasm32-wasip1", "wasm32-wasip1-threads"),
]

def _collisions():
    """Returns {constraint key: [triples]} for any colliding projection."""
    by_key = {}
    for t in ALL_TARGET_TRIPLES:
        key = ",".join(sorted(triple_to_rust_constraint_set(t)))
        by_key.setdefault(key, []).append(t)
    return {key: triples for key, triples in by_key.items() if len(triples) > 1}

def _uniqueness_impl(ctx):
    env = unittest.begin(ctx)

    collisions = _collisions()
    asserts.equals(
        env,
        {},
        collisions,
        "triples projecting to identical constraint sets (ambiguous match): %s" % collisions,
    )

    return unittest.end(env)

def _pairs_differ_impl(ctx):
    env = unittest.begin(ctx)

    for a, b in _PAIRS:
        set_a = sorted(triple_to_rust_constraint_set(a))
        set_b = sorted(triple_to_rust_constraint_set(b))
        asserts.true(
            env,
            set_a != set_b,
            "%s and %s must project to distinct constraint sets, got %s" % (a, b, set_a),
        )

        # Each member must carry exactly one disambiguator, and a different one.
        dis_a = [c for c in set_a if c in _DISAMBIGUATOR_CONSTRAINTS]
        dis_b = [c for c in set_b if c in _DISAMBIGUATOR_CONSTRAINTS]
        asserts.equals(env, 1, len(dis_a), "%s should carry one disambiguator, got %s" % (a, dis_a))
        asserts.equals(env, 1, len(dis_b), "%s should carry one disambiguator, got %s" % (b, dis_b))
        asserts.true(env, dis_a != dis_b, "%s and %s share a disambiguator %s" % (a, b, dis_a))

    return unittest.end(env)

def _lone_unchanged_impl(ctx):
    env = unittest.begin(ctx)

    for t in _LONE_TRIPLES:
        constraints = triple_to_rust_constraint_set(t)
        extra = [c for c in constraints if c in _DISAMBIGUATOR_CONSTRAINTS]
        asserts.equals(
            env,
            [],
            extra,
            "lone target %s must not gain a disambiguator constraint, got %s" % (t, extra),
        )

    return unittest.end(env)

uniqueness_test = unittest.make(_uniqueness_impl)
pairs_differ_test = unittest.make(_pairs_differ_impl)
lone_unchanged_test = unittest.make(_lone_unchanged_impl)

def triples_tests():
    return unittest.suite(
        "triples_tests",
        uniqueness_test,
        pairs_differ_test,
        lone_unchanged_test,
    )
