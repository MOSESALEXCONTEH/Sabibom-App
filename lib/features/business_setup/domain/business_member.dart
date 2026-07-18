class BusinessMember {
  const BusinessMember({
    required this.userId,
    required this.role,
    required this.status,
  });

  factory BusinessMember.owner(String userId) {
    return BusinessMember(userId: userId, role: 'owner', status: 'active');
  }

  final String userId;
  final String role;
  final String status;

  Map<String, Object?> toMap() {
    return <String, Object?>{'userId': userId, 'role': role, 'status': status};
  }
}
