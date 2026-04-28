import 'package:meta/meta.dart';

import '../../signal/species_baselines.dart';

@immutable
class Pet {
  const Pet({
    required this.id,
    required this.clinicId,
    required this.name,
    required this.species,
    required this.breed,
    required this.sex,
    required this.weightKg,
    required this.dateOfBirth,
    required this.ownerName,
    required this.ownerEmail,
    required this.ownerPhone,
    required this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String clinicId;
  final String name;
  final Species species;
  final String breed;
  final PetSex sex;
  final double weightKg;
  final DateTime dateOfBirth;
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get ageMonths {
    final now = DateTime.now();
    return (now.year - dateOfBirth.year) * 12 +
        (now.month - dateOfBirth.month);
  }

  SpeciesBaseline get baseline => baselineFor(species, weightKg);

  Pet copyWith({
    String? name,
    Species? species,
    String? breed,
    PetSex? sex,
    double? weightKg,
    DateTime? dateOfBirth,
    String? ownerName,
    String? ownerEmail,
    String? ownerPhone,
    String? notes,
  }) =>
      Pet(
        id: id,
        clinicId: clinicId,
        name: name ?? this.name,
        species: species ?? this.species,
        breed: breed ?? this.breed,
        sex: sex ?? this.sex,
        weightKg: weightKg ?? this.weightKg,
        dateOfBirth: dateOfBirth ?? this.dateOfBirth,
        ownerName: ownerName ?? this.ownerName,
        ownerEmail: ownerEmail ?? this.ownerEmail,
        ownerPhone: ownerPhone ?? this.ownerPhone,
        notes: notes ?? this.notes,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'clinic_id': clinicId,
        'name': name,
        'species': species.name,
        'breed': breed,
        'sex': sex.name,
        'weight_kg': weightKg,
        'date_of_birth': dateOfBirth.toIso8601String(),
        'owner_name': ownerName,
        'owner_email': ownerEmail,
        'owner_phone': ownerPhone,
        'notes': notes,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

enum PetSex { male, female, neutered, spayed, unknown }
