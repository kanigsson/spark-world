#!/usr/bin/env python3
"""Generate PROOF_STATUS.md from the output of a gnatprove run.

gnatprove writes one <unit>.spark file per analysed unit into the gnatprove
subdirectory of the project's object directory. Those files are JSON and
carry everything the status table needs: which entities are in SPARK, and one
record per check with its rule and whether it was proved.

    tools/proof_status.py            # rewrite PROOF_STATUS.md
    tools/proof_status.py --check    # fail if PROOF_STATUS.md is out of date

The assurance level of a unit is computed from the checks, not declared, up to
gold. Platinum cannot be computed -- it is a claim about the specification
being complete, not about the checks passing -- so it is declared in
proof_levels.json and accepted only for a unit that already reaches gold.
"""

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
DEFAULT_SPARK_DIR = ROOT / "obj" / "lib" / "gnatprove"
OUTPUT = ROOT / "PROOF_STATUS.md"
DECLARATIONS = ROOT / "proof_levels.json"

#  The categories of the summary table gnatprove prints, and the assurance
#  level each one belongs to. The mapping mirrors VC_Kind_To_Summary and
#  Flow_Kind_To_Summary in the gnatprove sources; a rule that is not listed is
#  reported rather than silently dropped, so that a new check kind cannot
#  quietly improve the level.
FLOW_CATEGORIES = {"Data Dependencies", "Flow Dependencies", "Initialization",
                   "Non-Aliasing"}
RUNTIME_CATEGORIES = {"Run-time Checks"}
FUNCTIONAL_CATEGORIES = {"Assertions", "Functional Contracts", "Termination",
                         "LSP Verification", "Concurrency"}

RUNTIME_RULES = {
    "VC_DIVISION_CHECK", "VC_INDEX_CHECK", "VC_OVERFLOW_CHECK",
    "VC_FP_OVERFLOW_CHECK", "VC_RANGE_CHECK", "VC_PREDICATE_CHECK",
    "VC_PREDICATE_CHECK_ON_DEFAULT_VALUE", "VC_INVARIANT_CHECK",
    "VC_INVARIANT_CHECK_ON_DEFAULT_VALUE", "VC_NULL_POINTER_DEREFERENCE",
    "VC_NULL_EXCLUSION", "VC_DYNAMIC_ACCESSIBILITY_CHECK", "VC_RESOURCE_LEAK",
    "VC_RESOURCE_LEAK_AT_END_OF_SCOPE", "VC_LENGTH_CHECK",
    "VC_DISCRIMINANT_CHECK", "VC_TAG_CHECK", "VC_CEILING_INTERRUPT",
    "VC_INTERRUPT_RESERVED", "VC_CEILING_PRIORITY_PROTOCOL",
    "VC_TASK_TERMINATION", "VC_RAISE", "VC_UNEXPECTED_PROGRAM_EXIT",
    "VC_UC_SOURCE", "VC_UC_TARGET", "VC_UC_SAME_SIZE", "VC_UC_ALIGN_OVERLAY",
    "VC_UC_ALIGN_UC", "VC_UNCHECKED_UNION_RESTRICTION", "VC_UC_VOLATILE",
    "VC_VALIDITY_CHECK", "CALL_TO_CURRENT_TASK",
}
ASSERTION_RULES = {
    "VC_ASSERT", "VC_ASSERT_PREMISE", "VC_ASSERT_STEP", "VC_LOOP_INVARIANT",
    "VC_LOOP_INVARIANT_INIT", "VC_LOOP_INVARIANT_PRESERV",
}
FUNCTIONAL_RULES = {
    "VC_INITIAL_CONDITION", "VC_DEFAULT_INITIAL_CONDITION", "VC_PRECONDITION",
    "VC_PRECONDITION_MAIN", "VC_POSTCONDITION", "VC_REFINED_POST",
    "VC_CONTRACT_CASE", "VC_DISJOINT_CASES", "VC_COMPLETE_CASES",
    "VC_EXCEPTIONAL_CASE", "VC_PROGRAM_EXIT_POST", "VC_EXIT_CASE",
    "VC_INLINE_CHECK", "VC_ITERABLE_CHECK", "VC_CONTAINER_AGGR_CHECK",
    "VC_RECLAMATION_CHECK", "VC_FEASIBLE_POST", "VC_MODIFIES",
}
TERMINATION_RULES = {
    "VC_LOOP_VARIANT", "VC_SUBPROGRAM_VARIANT", "VC_TERMINATION_CHECK",
    "SUBPROGRAM_TERMINATION", "CALL_IN_TYPE_INVARIANT",
}
LSP_RULES = {
    "VC_WEAKER_PRE", "VC_TRIVIAL_WEAKER_PRE", "VC_STRONGER_POST",
    "VC_WEAKER_CLASSWIDE_PRE", "VC_STRONGER_CLASSWIDE_POST",
    "VC_WEAKER_PRE_ACCESS", "VC_STRONGER_POST_ACCESS",
}
INIT_RULES = {
    "VC_INITIALIZATION_CHECK", "IMPOSSIBLE_TO_INITIALIZE_STATE",
    "INITIALIZES_WRONG", "UNINITIALIZED", "DEFAULT_INITIALIZATION_MISMATCH",
}
DATA_DEP_RULES = {
    "CRITICAL_GLOBAL_MISSING", "GLOBAL_MISSING", "GLOBAL_WRONG",
    "EXPORT_DEPENDS_ON_PROOF_IN", "GHOST_WRONG", "HIDDEN_UNEXPOSED_STATE",
    "ILLEGAL_UPDATE", "NON_VOLATILE_FUNCTION_WITH_VOLATILE_EFFECTS",
    "REFINED_STATE_WRONG", "SIDE_EFFECTS", "UNUSED_GLOBAL",
}
FLOW_DEP_RULES = {
    "DEPENDS_MISSING", "DEPENDS_MISSING_CLAUSE", "DEPENDS_NULL",
    "DEPENDS_WRONG",
}
CONCURRENCY_RULES = {"CONCURRENT_ACCESS", "POTENTIALLY_BLOCKING_IN_PROTECTED"}
NOT_COUNTED_RULES = {
    "EMPTY_TAG", "DEAD_CODE", "INEFFECTIVE", "INOUT_ONLY_READ",
    "MISSING_RETURN", "NOT_CONSTANT_AFTER_ELABORATION",
    "REFERENCE_TO_NON_CAE_VARIABLE", "STABLE", "UNUSED_INITIAL_VALUE",
    "UNUSED_VARIABLE",
}

CATEGORY_OF_RULE = {}
for rules, category in ((RUNTIME_RULES, "Run-time Checks"),
                        (ASSERTION_RULES, "Assertions"),
                        (FUNCTIONAL_RULES, "Functional Contracts"),
                        (TERMINATION_RULES, "Termination"),
                        (LSP_RULES, "LSP Verification"),
                        (INIT_RULES, "Initialization"),
                        (DATA_DEP_RULES, "Data Dependencies"),
                        (FLOW_DEP_RULES, "Flow Dependencies"),
                        (CONCURRENCY_RULES, "Concurrency"),
                        ({"ALIASING"}, "Non-Aliasing")):
    for rule in rules:
        CATEGORY_OF_RULE[rule] = category

LEVELS = ["not analyzed", "stone", "bronze", "silver", "gold", "platinum"]


class Unit:
    def __init__(self, path):
        self.path = path
        data = json.loads(path.read_text())
        self.name = unit_name(path.stem)
        spark = data.get("spark", {})
        self.entities = len(spark)
        self.in_spark = sum(1 for status in spark.values() if status == "all")
        self.spec_only = sum(1 for status in spark.values() if status == "spec")
        self.analyzed = not data.get("skip_proof", False)
        self.total = 0
        self.unproved = 0
        self.unproved_by_category = {}
        self.unknown_rules = set()
        for check in data.get("proof", []) + data.get("flow", []):
            rule = check.get("rule", "")
            if rule in NOT_COUNTED_RULES:
                continue
            category = CATEGORY_OF_RULE.get(rule)
            if category is None:
                self.unknown_rules.add(rule)
                category = "Uncategorized"
            self.total += 1
            if check.get("severity") != "info":
                self.unproved += 1
                self.unproved_by_category[category] = \
                    self.unproved_by_category.get(category, 0) + 1

    @property
    def proved(self):
        return self.total - self.unproved

    @property
    def spark_percent(self):
        if self.entities == 0:
            return 100
        return round(100 * self.in_spark / self.entities)

    def unproved_in(self, categories):
        return sum(count for category, count in self.unproved_by_category.items()
                   if category in categories)

    @property
    def attained_level(self):
        """The highest level the checks support. Platinum is never attained
        by computation; it is a claim about the specification."""
        if self.unknown_rules:
            return "not analyzed"
        if not self.analyzed or self.in_spark < self.entities:
            return "stone"
        if self.unproved_in(FLOW_CATEGORIES):
            return "stone"
        if self.unproved_in(RUNTIME_CATEGORIES):
            return "bronze"
        if self.unproved_in(FUNCTIONAL_CATEGORIES):
            return "silver"
        return "gold"

    @property
    def has_checks(self):
        return self.total > 0


def unit_name(stem):
    return ".".join(part.title() for part in stem.split("-"))


def bar(proved, total, width=10):
    if total == 0:
        return ""
    filled = round(width * proved / total)
    if filled == width and proved < total:
        filled = width - 1          # never show a full bar for a partial proof
    return "`" + "█" * filled + "░" * (width - filled) + "`"


def declared_levels():
    if not DECLARATIONS.exists():
        return {}
    return json.loads(DECLARATIONS.read_text())


def render(units, declarations):
    lines = [
        "# Proof status",
        "",
        "Generated by [`tools/proof_status.py`](tools/proof_status.py) from the",
        "output of `gnatprove -P ore_lib.gpr`; do not edit by hand. The proof",
        "switches are in `ore_lib.gpr`.",
        "",
        "The level of a unit is computed from the checks — flow clean is bronze,",
        "no run-time errors is silver, contracts proved as well is gold. Platinum",
        "says the specification is complete, which no tool can decide, so it is",
        "declared in [`proof_levels.json`](proof_levels.json) and accepted only",
        "for a unit that already reaches gold.",
        "",
        "| Unit | SPARK | Level | Proved | Checks |",
        "| --- | --- | --- | --- | --- |",
    ]
    total_checks = total_proved = 0
    for unit in units:
        total_checks += unit.total
        total_proved += unit.proved
        declaration = declarations.get(unit.name, {})
        level = declaration.get("level", unit.attained_level)
        note = declaration.get("note", "")
        if not unit.has_checks:
            level_cell = "—"
            proved_cell = "—"
            checks_cell = note or "declarations only"
        else:
            level_cell = level
            proved_cell = f"{bar(unit.proved, unit.total)} {round(100 * unit.proved / unit.total)}%"
            checks_cell = f"{unit.proved}/{unit.total} checks"
            if unit.unproved:
                worst = ", ".join(f"{count} {category.lower()}" for category, count
                                  in sorted(unit.unproved_by_category.items()))
                checks_cell += f" — unproved: {worst}"
            if note:
                checks_cell += f" — {note}"
        lines.append(
            f"| `{unit.name}` | {unit.spark_percent}% "
            f"({unit.in_spark}/{unit.entities} entities) | {level_cell} | "
            f"{proved_cell} | {checks_cell} |")
    lines += [
        "",
        f"Total: {total_proved} of {total_checks} checks proved.",
        "",
    ]
    return "\n".join(lines)


def check_declarations(units, declarations):
    """A declared level may not exceed what the checks support, except that
    platinum is allowed on top of gold."""
    errors = []
    by_name = {unit.name: unit for unit in units}
    for name, declaration in declarations.items():
        unit = by_name.get(name)
        if unit is None:
            errors.append(f"{name}: declared in {DECLARATIONS.name} but not analyzed")
            continue
        declared = declaration.get("level")
        if declared is None:          # a note only; the level stays computed
            continue
        if declared not in LEVELS:
            errors.append(f"{name}: unknown level {declared!r}")
            continue
        attained = unit.attained_level
        if declared == "platinum":
            if attained != "gold":
                errors.append(f"{name}: platinum declared but the checks only "
                              f"support {attained}")
        elif LEVELS.index(declared) > LEVELS.index(attained):
            errors.append(f"{name}: {declared} declared but the checks only "
                          f"support {attained}")
    for unit in units:
        if unit.unknown_rules:
            errors.append(f"{unit.name}: unrecognized check rules "
                          f"{sorted(unit.unknown_rules)}; update {pathlib.Path(__file__).name}")
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--spark-dir", type=pathlib.Path, default=DEFAULT_SPARK_DIR,
                        help="directory holding the .spark files")
    parser.add_argument("--check", action="store_true",
                        help="do not write; fail if the file is out of date")
    args = parser.parse_args()

    files = sorted(args.spark_dir.glob("*.spark"))
    if not files:
        sys.exit(f"no .spark files in {args.spark_dir}; run gnatprove first")
    units = [Unit(path) for path in files]
    declarations = declared_levels()

    errors = check_declarations(units, declarations)
    if errors:
        for error in errors:
            print(f"error: {error}", file=sys.stderr)
        sys.exit(1)

    content = render(units, declarations)
    if args.check:
        current = OUTPUT.read_text() if OUTPUT.exists() else ""
        if current != content:
            sys.exit(f"{OUTPUT.name} is out of date; run tools/proof_status.py")
        print(f"{OUTPUT.name} is up to date")
        return
    OUTPUT.write_text(content)
    print(f"wrote {OUTPUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
