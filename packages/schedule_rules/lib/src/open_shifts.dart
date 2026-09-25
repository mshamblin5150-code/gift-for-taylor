part of '../schedule_rules.dart';

enum PickupStatus { pending, approved, declined }

final class CoveragePoolConfig {
  const CoveragePoolConfig({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.retired,
    required this.jobRoles,
    this.floorRole,
  });

  final String id;
  final String name;
  final int sortOrder;
  final bool retired;
  final Set<JobRole> jobRoles;
  final JobRole? floorRole;
}

final class CoverageRulePlan {
  const CoverageRulePlan({
    required this.workDate,
    required this.pool,
    required this.window,
    required this.floorRole,
    required this.postFloor,
    required this.postOrdinary,
    required this.withdrawFloor,
    required this.withdrawOrdinary,
  });

  factory CoverageRulePlan.fromJson(Map<String, dynamic> json) =>
      CoverageRulePlan(
        workDate: DateTime.parse(json['work_date'] as String),
        pool: json['pool'] as String,
        window: CoverageWindow.fromValue(json['window'] as String),
        floorRole: switch (json['floor_role']) {
          final String value => JobRole.fromValue(value),
          _ => null,
        },
        postFloor: json['post_floor'] as int,
        postOrdinary: json['post_ordinary'] as int,
        withdrawFloor: json['withdraw_floor'] as int,
        withdrawOrdinary: json['withdraw_ordinary'] as int,
      );

  final DateTime workDate;
  final String pool;
  final CoverageWindow window;
  final JobRole? floorRole;
  final int postFloor;
  final int postOrdinary;
  final int withdrawFloor;
  final int withdrawOrdinary;

  Map<String, dynamic> toJson() => {
    'work_date': workDate.toIso8601String().substring(0, 10),
    'pool': pool,
    'window': window.value,
    'floor_role': floorRole?.value,
    'post_floor': postFloor,
    'post_ordinary': postOrdinary,
    'withdraw_floor': withdrawFloor,
    'withdraw_ordinary': withdrawOrdinary,
  };
}

final class CoverageRuleChoice {
  const CoverageRuleChoice({
    required this.workDate,
    required this.pool,
    required this.window,
    required this.floorRole,
    this.floorShiftCode,
    this.ordinaryRole,
    this.ordinaryShiftCode,
  });

  final DateTime workDate;
  final String pool;
  final CoverageWindow window;
  final JobRole? floorRole;
  final String? floorShiftCode;
  final JobRole? ordinaryRole;
  final String? ordinaryShiftCode;

  Map<String, dynamic> toJson() => {
    'work_date': workDate.toIso8601String().substring(0, 10),
    'pool': pool,
    'window': window.value,
    'floor_role': floorRole?.value,
    'floor_shift_code': floorShiftCode,
    'ordinary_role': ordinaryRole?.value,
    'ordinary_shift_code': ordinaryShiftCode,
  };
}

final class OpenShift {
  const OpenShift({
    required this.id,
    required this.sectionId,
    required this.date,
    required this.shiftCode,
    this.originalStaffMemberId,
    required this.jobRole,
    this.requiresApproval = true,
  });
  final String id;
  final String? sectionId;
  final DateTime date;
  final String shiftCode;
  final String? originalStaffMemberId;
  final JobRole jobRole;
  final bool requiresApproval;
}

final class SectionStaffing {
  const SectionStaffing({
    required this.pool,
    required this.coverageWindow,
    required this.date,
    required this.minimum,
    required this.rnFloor,
    required this.workingCount,
    required this.rnCount,
    required this.openCount,
    required this.rnOpenCount,
    required this.shortCount,
    required this.rnShortCount,
    required this.unpostedCount,
    this.weekdayMinimum,
    this.dateMinimum,
    this.floorRole,
  });
  final CoveragePool pool;
  final CoverageWindow coverageWindow;
  final DateTime date;
  final int? minimum;
  final int? rnFloor;
  final int workingCount;
  final int rnCount;
  final int openCount;
  final int rnOpenCount;

  /// The Shortfall returned by the staffing read.
  final int? shortCount;
  final int? rnShortCount;
  final int? unpostedCount;
  final int? weekdayMinimum;
  final int? dateMinimum;
  final JobRole? floorRole;
}

final class OpenShiftPickup {
  const OpenShiftPickup({
    required this.id,
    required this.openShiftId,
    required this.staffMemberId,
    required this.status,
  });
  final String id;
  final String openShiftId;
  final String staffMemberId;
  final PickupStatus status;
}

abstract interface class OpenShiftStore {
  Future<List<CoveragePoolConfig>> coveragePoolsOn(DateTime date);
  Future<List<Map<String, dynamic>>> coverageRuleHistory();
  Future<List<CoverageRulePlan>> previewCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
  );
  Future<void> commitCoveragePools(
    DateTime effectiveFrom,
    List<CoveragePoolConfig> pools,
    List<CoverageRulePlan> plan,
    List<CoverageRuleChoice> choices,
  );
  Future<List<CoverageRulePlan>> previewStandingMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    DateTime effectiveFrom,
    int minimum,
    JobRole? floorRole,
    int floor,
  );
  Future<void> commitStandingMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    DateTime effectiveFrom,
    int minimum,
    JobRole? floorRole,
    int floor,
    List<CoverageRulePlan> plan,
    List<CoverageRuleChoice> choices,
  );
  Future<List<CoverageRulePlan>> previewDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    JobRole? floorRole,
    int floor,
  );
  Future<void> commitDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    JobRole? floorRole,
    int floor,
    List<CoverageRulePlan> plan,
    List<CoverageRuleChoice> choices,
  );
  Future<List<OpenShift>> openShifts();
  Future<int> hiddenOpenShiftCount(DateTime month);
  Future<List<OpenShiftPickup>> pickups();
  Future<void> requestPickup(String openShiftId);
  Future<void> approvePickup(String pickupId);
  Future<void> declinePickup(String pickupId, {String? reason});
  Future<bool> approvalDefault();
  Future<void> setApprovalDefault(bool requiresApproval);
  Future<void> setShiftApproval(String openShiftId, bool requiresApproval);
  Future<List<SectionStaffing>> staffingForMonth(DateTime month);
  Future<void> setWeekdayMinimum(
    CoveragePool pool,
    CoverageWindow window,
    int weekday,
    int minimum,
    int rnFloor,
  );
  Future<void> setDateMinimum(
    CoveragePool pool,
    CoverageWindow window,
    DateTime date,
    int? minimum,
    int? rnFloor,
  );
  Future<int> postOpenShifts(
    DateTime date,
    String shiftCode,
    CoveragePool pool,
    int count, {
    bool fillGap = false,
  });
  Stream<void> updates();
}
