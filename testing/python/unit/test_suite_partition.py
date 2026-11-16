"""Guard against silently omitting or double-counting backend coverage."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from run_checks import validate_partition


class SuitePartitionTests(unittest.TestCase):
    def setUp(self):
        self.groups = {stage: [stage + '::case'] for stage in ('unit', 'integration', 'database', 'gtfs', 'live')}
        self.discovered = [case for cases in self.groups.values() for case in cases]

    def test_complete_disjoint_inventory_is_accepted(self):
        validate_partition(self.groups, self.discovered)

    def test_new_test_requires_classification(self):
        with self.assertRaisesRegex(ValueError, 'unclassified=.*new_case'):
            validate_partition(self.groups, self.discovered + ['new_case'])

    def test_overlapping_stages_are_rejected(self):
        self.groups['integration'].append('unit::case')
        with self.assertRaisesRegex(ValueError, 'duplicates=.*unit::case'):
            validate_partition(self.groups, self.discovered)

    def test_removed_or_empty_groups_are_rejected(self):
        self.groups['unit'] = []
        with self.assertRaisesRegex(ValueError, 'empty=.*unit'):
            validate_partition(self.groups, self.discovered)
        with self.assertRaisesRegex(ValueError, 'removed=.*unit::case'):
            validate_partition(self.groups | {'unit': ['unit::case']}, self.discovered[1:])
