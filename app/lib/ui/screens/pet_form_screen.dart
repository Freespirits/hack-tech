import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../data/models/pet.dart';
import '../../signal/species_baselines.dart';

class PetFormScreen extends ConsumerStatefulWidget {
  const PetFormScreen({super.key});

  @override
  ConsumerState<PetFormScreen> createState() => _PetFormScreenState();
}

class _PetFormScreenState extends ConsumerState<PetFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _breed = TextEditingController();
  final _weight = TextEditingController();
  final _ownerName = TextEditingController();
  final _ownerEmail = TextEditingController();
  final _ownerPhone = TextEditingController();
  Species _species = Species.dog;
  PetSex _sex = PetSex.unknown;
  DateTime _dob = DateTime.now().subtract(const Duration(days: 365));
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _breed.dispose();
    _weight.dispose();
    _ownerName.dispose();
    _ownerEmail.dispose();
    _ownerPhone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final clinicId = ref.read(activeClinicIdProvider);
    if (clinicId == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(petRepositoryProvider).create(
            clinicId: clinicId,
            name: _name.text.trim(),
            species: _species,
            breed: _breed.text.trim(),
            sex: _sex,
            weightKg: double.parse(_weight.text.trim()),
            dateOfBirth: _dob,
            ownerName: _ownerName.text.trim(),
            ownerEmail: _ownerEmail.text.trim(),
            ownerPhone: _ownerPhone.text.trim(),
          );
      if (mounted) context.pop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add patient')),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<Species>(
              value: _species,
              decoration: const InputDecoration(labelText: 'Species'),
              items: Species.values
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(_speciesLabel(s))))
                  .toList(),
              onChanged: (v) => setState(() => _species = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _breed,
              decoration: const InputDecoration(labelText: 'Breed (optional)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<PetSex>(
              value: _sex,
              decoration: const InputDecoration(labelText: 'Sex'),
              items: PetSex.values
                  .map((s) =>
                      DropdownMenuItem(value: s, child: Text(_sexLabel(s))))
                  .toList(),
              onChanged: (v) => setState(() => _sex = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _weight,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Weight (kg)'),
              validator: (v) {
                if (v == null) return 'Required';
                final n = double.tryParse(v.trim());
                if (n == null || n <= 0) return 'Enter a positive number';
                return null;
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Date of birth'),
              subtitle: Text(_dob.toString().split(' ').first),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _dob,
                  firstDate: DateTime(1990),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _dob = picked);
              },
            ),
            const Divider(height: 32),
            Text('Owner', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextFormField(
              controller: _ownerName,
              decoration: const InputDecoration(labelText: 'Owner name'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ownerEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Owner email'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _ownerPhone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Owner phone'),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save patient'),
            ),
          ],
        ),
      ),
    );
  }

  String _speciesLabel(Species s) => switch (s) {
        Species.dog => 'Dog',
        Species.cat => 'Cat',
        Species.rabbit => 'Rabbit',
        Species.ferret => 'Ferret',
        Species.otherSmallMammal => 'Small mammal',
      };

  String _sexLabel(PetSex s) => switch (s) {
        PetSex.male => 'Male (intact)',
        PetSex.female => 'Female (intact)',
        PetSex.neutered => 'Neutered male',
        PetSex.spayed => 'Spayed female',
        PetSex.unknown => 'Unknown',
      };
}
