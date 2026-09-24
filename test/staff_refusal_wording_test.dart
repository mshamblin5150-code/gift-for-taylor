import 'package:er_schedule/staff/refusal_wording.dart';
import 'package:er_schedule/staff/staff_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every Manager handover refusal has actionable page wording', () {
    const cases = {
      ManagerHandoverRefusal.managerAccessChanged:
          'Ask the Maintainer to restore your Manager access before '
          'transferring Manager.',
      ManagerHandoverRefusal.noActiveManager:
          'Ask the Maintainer to restore an active Manager before '
          'transferring Manager.',
      ManagerHandoverRefusal.sameStaffMember:
          'Choose another Staff member before transferring Manager.',
      ManagerHandoverRefusal.retainedSectionMissing:
          'Review your Night scheduler Sections because one selected for '
          'your access after handover no longer exists.',
      ManagerHandoverRefusal.successorNoAccount:
          "Resend this Staff member's Invite and ask them to accept it before "
          'transferring Manager.',
      ManagerHandoverRefusal.successorInvitePending:
          "Confirm this Staff member's accepted Invite before transferring "
          'Manager.',
      ManagerHandoverRefusal.successorAccountRevoked:
          "Resend this Staff member's Invite to restore their account before "
          'transferring Manager.',
      ManagerHandoverRefusal.successorInactive:
          'Reactivate this Staff member before transferring Manager.',
      ManagerHandoverRefusal.successorAlreadyManager:
          'Choose another Staff member because this person is already the '
          'Manager.',
      ManagerHandoverRefusal.successorNoCurrentSection:
          'Assign this Staff member a current Section before transferring '
          'Manager.',
    };

    for (final MapEntry(key: reason, value: wording) in cases.entries) {
      expect(
        managerHandoverRefusalWording(ManagerHandoverRefused(reason)),
        wording,
      );
    }
  });

  test('every Invite acceptance refusal has actionable page wording', () {
    const cases = {
      InviteAcceptanceRefusal.staffAcceptancePending:
          'Wait for the Manager or an Administrator to confirm your Invite '
          'acceptance before signing in.',
      InviteAcceptanceRefusal.staffAlreadyAccepted:
          'This Invite was already accepted, so sign in with the email that '
          'accepted it or ask your Manager to resend it.',
      InviteAcceptanceRefusal.emailAcceptancePending:
          'Ask the Manager or an Administrator to confirm the Invite this '
          'email already accepted.',
      InviteAcceptanceRefusal.accountMissingEmail:
          'Sign out and use an account with an email address before accepting '
          'this Invite.',
    };

    for (final MapEntry(key: reason, value: wording) in cases.entries) {
      expect(
        inviteAcceptanceRefusalWording(InviteAcceptanceRefused(reason)),
        wording,
      );
    }
  });

  test('unmapped failures keep the generic page fallback', () {
    expect(managerHandoverRefusalWording(StateError('failure')), isNull);
    expect(inviteAcceptanceRefusalWording(StateError('failure')), isNull);
  });
}
