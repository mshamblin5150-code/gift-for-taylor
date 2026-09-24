import 'package:schedule_rules/schedule_rules.dart';

import '../maintainer/repair_gateway.dart';

/// Decode the single row returned by the database's current_access function.
Access accessFromRow(Map<String, dynamic> values) => Access(
  grants: Grants(
    manager: values['manager'] as bool,
    administrator: values['administrator'] as bool,
    nightSchedulerSectionIds: {
      for (final id in values['night_scheduler_section_ids'] as List<dynamic>)
        id as String,
    },
  ),
  maintainer: values['maintainer'] as bool,
  ownStaffMemberId: values['staff_member_id'] as String?,
  activeRepair: maintainerRepairFromRow(values),
);
