import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/di.dart';
import '../../data/models/pet.dart';

class PetListScreen extends ConsumerWidget {
  const PetListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clinicId = ref.watch(activeClinicIdProvider);
    if (clinicId == null) {
      return const Scaffold(
        body: Center(child: Text('No active clinic — sign in again.')),
      );
    }
    final petsAsync = ref.watch(_petsStreamProvider(clinicId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Patients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () async {
              await ref.read(supabaseProvider).signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/pets/new'),
        icon: const Icon(Icons.add),
        label: const Text('Add patient'),
      ),
      body: petsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (pets) => pets.isEmpty
            ? const _EmptyState()
            : ListView.separated(
                padding: const EdgeInsets.all(8),
                itemCount: pets.length,
                separatorBuilder: (_, __) => const SizedBox(height: 4),
                itemBuilder: (_, i) => _PetTile(pet: pets[i]),
              ),
      ),
    );
  }
}

final _petsStreamProvider =
    StreamProvider.family.autoDispose<List<Pet>, String>((ref, clinicId) {
  final repo = ref.watch(petRepositoryProvider);
  return repo.watchAll(clinicId);
});

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pets, size: 64),
            SizedBox(height: 12),
            Text('No patients yet — add your first one to start.'),
          ],
        ),
      ),
    );
  }
}

class _PetTile extends StatelessWidget {
  const _PetTile({required this.pet});
  final Pet pet;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text(pet.name.characters.first)),
        title: Text(pet.name),
        subtitle: Text(
          '${_speciesLabel(pet.species)} • ${pet.breed.isEmpty ? '—' : pet.breed} '
          '• ${pet.weightKg.toStringAsFixed(1)} kg',
        ),
        trailing: FilledButton.icon(
          icon: const Icon(Icons.bluetooth_searching),
          label: const Text('Monitor'),
          onPressed: () => context.push('/pets/${pet.id}/session'),
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
}
