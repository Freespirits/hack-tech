import 'package:meta/meta.dart';

@immutable
class Clinic {
  const Clinic({
    required this.id,
    required this.name,
    required this.address,
    required this.phone,
    required this.email,
    required this.subscriptionTier,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String address;
  final String phone;
  final String email;
  final SubscriptionTier subscriptionTier;
  final DateTime createdAt;
}

enum SubscriptionTier { free, pro, enterprise }

@immutable
class ClinicMember {
  const ClinicMember({
    required this.userId,
    required this.clinicId,
    required this.role,
    required this.displayName,
    required this.email,
  });

  final String userId;
  final String clinicId;
  final ClinicRole role;
  final String displayName;
  final String email;
}

enum ClinicRole {
  owner,
  veterinarian,
  technician,
  receptionist,
  readonly,
}
