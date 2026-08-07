/// User-facing team/permission error messages (no raw Firebase/Vercel bodies).
class TeamException implements Exception {
  const TeamException(this.message, {this.code});

  final String message;
  final String? code;

  static const unauthenticated =
      TeamException('Your session expired. Please sign in again.',
          code: 'unauthenticated');
  static const permissionDenied = TeamException(
    'You do not have permission to perform this action.',
    code: 'permission_denied',
  );
  static const invitationExpired = TeamException(
    'This invitation has expired. Ask the business owner to send another one.',
    code: 'invitation_expired',
  );
  static const invitationUsed = TeamException(
    'This invitation has already been accepted or cancelled.',
    code: 'invitation_used',
  );
  static const existingMember = TeamException(
    'This person is already a member of the business.',
    code: 'existing_member',
  );
  static const lastOwner = TeamException(
    'This business must always have at least one active owner.',
    code: 'last_owner',
  );
  static const approvalHandled = TeamException(
    'This approval request has already been completed.',
    code: 'approval_handled',
  );
  static const network = TeamException(
    'Check your internet connection and try again.',
    code: 'network',
  );
  static const unknown = TeamException(
    'Something went wrong. Please try again.',
    code: 'unknown',
  );
  static const noBusiness = TeamException(
    'Create or select a business before managing your team.',
    code: 'no_business',
  );

  static TeamException fromObject(Object error) {
    if (error is TeamException) return error;
    final text = '$error'.toLowerCase();
    if (text.contains('permission-denied') || text.contains('permission_denied')) {
      return permissionDenied;
    }
    if (text.contains('unauthenticated') || text.contains('auth')) {
      return unauthenticated;
    }
    if (text.contains('network') || text.contains('socket')) {
      return network;
    }
    if (text.contains('last_owner') || text.contains('last owner')) {
      return lastOwner;
    }
    return unknown;
  }

  @override
  String toString() => message;
}
