import 'package:supabase_flutter/supabase_flutter.dart';

import 'cloud_models.dart';

class FarshaRepository {
  FarshaRepository(this.client);

  final SupabaseClient client;

  String get userId => client.auth.currentUser!.id;

  Future<UserProfile> loadProfile() async {
    final row = await client.from('profiles').select().eq('id', userId).single();
    return UserProfile.fromMap(row);
  }

  Future<List<InstitutionMembership>> loadMemberships() async {
    final rows = await client
        .from('institution_memberships')
        .select('institution_id,role,status,institutions(name)')
        .eq('user_id', userId)
        .eq('status', 'active');
    return (rows as List)
        .map((row) => InstitutionMembership.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  Future<String> createInstitution({
    required String name,
    required String commercialRegistration,
    required String taxNumber,
    required String address,
    required String phone,
    required String email,
  }) async {
    final result = await client.rpc('create_institution', params: {
      'p_name': name,
      'p_cr': commercialRegistration,
      'p_tax': taxNumber,
      'p_address': address,
      'p_phone': phone,
      'p_email': email,
    });
    return result as String;
  }

  Future<String> claimInvitation(String code) async {
    final result = await client.rpc(
      'claim_institution_invitation',
      params: {'p_code': code},
    );
    return result as String;
  }

  Future<Map<String, int>> loadInstitutionCounts(String institutionId) async {
    final suppliers = await client
        .from('suppliers')
        .select('id')
        .eq('institution_id', institutionId);
    final inventory = await client
        .from('inventory_items')
        .select('id')
        .eq('institution_id', institutionId);
    final sales = await client
        .from('sales')
        .select('id')
        .eq('institution_id', institutionId);
    return {
      'suppliers': suppliers.length,
      'inventory': inventory.length,
      'sales': sales.length,
    };
  }

  Future<List<Map<String, dynamic>>> loadMembers(String institutionId) async {
    final rows = await client
        .from('institution_memberships')
        .select('user_id,role,status,work_plan,commission_rate,monthly_salary,profiles(full_name,phone)')
        .eq('institution_id', institutionId);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<String> inviteMember({
    required String institutionId,
    required String phone,
    required InstitutionRole role,
    String workPlan = 'commission',
    double commissionRate = .5,
    double monthlySalary = 0,
  }) async {
    final row = await client
        .from('institution_invitations')
        .insert({
          'institution_id': institutionId,
          'phone': phone,
          'role': role.name,
          'work_plan': workPlan,
          'commission_rate': commissionRate,
          'monthly_salary': monthlySalary,
          'created_by': userId,
        })
        .select('invite_code')
        .single();
    return row['invite_code'] as String;
  }

  Future<String> connectDriver({
    required String institutionId,
    required String phone,
  }) async {
    final result = await client.rpc('connect_driver', params: {
      'p_institution_id': institutionId,
      'p_phone': phone,
    });
    return result as String;
  }

  Future<List<Map<String, dynamic>>> loadConnectedDrivers(String institutionId) async {
    final rows = await client.rpc('list_connected_drivers', params: {
      'p_institution_id': institutionId,
    });
    return List<Map<String, dynamic>>.from(rows as List);
  }

  Future<List<DriverTrip>> loadDriverTrips() async {
    final rows = await client
        .from('driver_trips')
        .select('id,trip_date,amount,payment_status,payment_method,institutions(name),profiles!driver_trips_seller_id_fkey(full_name)')
        .eq('driver_id', userId)
        .order('trip_date', ascending: false);
    return (rows as List)
        .map((row) => DriverTrip.fromMap(row as Map<String, dynamic>))
        .toList();
  }
}
