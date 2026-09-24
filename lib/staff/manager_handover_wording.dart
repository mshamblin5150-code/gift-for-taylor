import 'staff_gateway.dart';

enum ManagerHandoverResolution {
  assignSection('Assign Section'),
  resendInvite('Resend Invite'),
  reviewInviteAcceptance('Review Invite acceptance'),
  reactivateStaff('Reactivate Staff member'),
  none('Resolve');

  const ManagerHandoverResolution(this.label);

  final String label;
}

typedef ManagerHandoverPresentation = ({
  ManagerHandoverResolution resolution,
  bool opensStaffDetails,
  String managerPageLabel,
});

ManagerHandoverPresentation managerHandoverPresentation(
  ManagerHandoverBlocker? blocker,
) => switch (blocker) {
  ManagerHandoverBlocker.noStaffAccount ||
  ManagerHandoverBlocker.accountRevoked => (
    resolution: ManagerHandoverResolution.resendInvite,
    opensStaffDetails: false,
    managerPageLabel: 'Open Staff list',
  ),
  ManagerHandoverBlocker.inviteAcceptancePending => (
    resolution: ManagerHandoverResolution.reviewInviteAcceptance,
    opensStaffDetails: false,
    managerPageLabel: 'Open Staff list',
  ),
  ManagerHandoverBlocker.inactive => (
    resolution: ManagerHandoverResolution.reactivateStaff,
    opensStaffDetails: false,
    managerPageLabel: 'Open Staff list',
  ),
  ManagerHandoverBlocker.noCurrentSection => (
    resolution: ManagerHandoverResolution.assignSection,
    opensStaffDetails: true,
    managerPageLabel: 'Assign Section',
  ),
  ManagerHandoverBlocker.alreadyManager || null => (
    resolution: ManagerHandoverResolution.none,
    opensStaffDetails: false,
    managerPageLabel: 'Open Staff list',
  ),
};

/// Presentation copy shared by the two Manager-handover surfaces.
String managerHandoverNextStep(ManagerHandoverCandidate candidate) =>
    switch (candidate.blocker) {
      ManagerHandoverBlocker.noStaffAccount =>
        '${candidate.displayName} has not completed an Invite. Resend the '
            'Invite and ask them to accept it before transferring Manager.',
      ManagerHandoverBlocker.inviteAcceptancePending =>
        '${candidate.displayName} accepted the Invite. Confirm it before '
            'transferring Manager.',
      ManagerHandoverBlocker.accountRevoked =>
        '${candidate.displayName}\'s account is revoked. Resend the Invite '
            'before transferring Manager.',
      ManagerHandoverBlocker.inactive =>
        '${candidate.displayName} is inactive. Reactivate this Staff member '
            'before transferring Manager.',
      ManagerHandoverBlocker.alreadyManager =>
        '${candidate.displayName} is already the Manager.',
      ManagerHandoverBlocker.noCurrentSection =>
        '${candidate.displayName} has no current Section. Assign a Section '
            'before transferring Manager.',
      null => '',
    };
