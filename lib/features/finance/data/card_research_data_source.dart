import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:work_tracker/core/supabase/supabase_providers.dart';
import 'package:work_tracker/features/finance/domain/card_research.dart';

abstract interface class CardResearchDataSource {
  Future<List<Map<String, dynamic>>> searchCatalog(
    CatalogProductIdentity identity,
  );

  Future<void> enqueueCatalogResearch(
    CatalogProductIdentity identity, {
    required String reason,
  });

  Future<Map<String, dynamic>> researchLive(CardResearchRequest request);
}

class SupabaseCardResearchDataSource implements CardResearchDataSource {
  const SupabaseCardResearchDataSource(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> searchCatalog(
    CatalogProductIdentity identity,
  ) async {
    final rows = await _client
        .schema(AppSchemas.finance)
        .rpc<List<dynamic>>(
          'catalog_search',
          params: identity.toSearchParams(),
        );
    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  @override
  Future<void> enqueueCatalogResearch(
    CatalogProductIdentity identity, {
    required String reason,
  }) async {
    await _client
        .schema(AppSchemas.finance)
        .rpc<dynamic>(
          'enqueue_catalog_research',
          params: identity.toEnqueueParams(reason),
        );
  }

  @override
  Future<Map<String, dynamic>> researchLive(CardResearchRequest request) async {
    final response = await _client.functions.invoke(
      'ai-card-research',
      body: request.toJson(),
    );
    return Map<String, dynamic>.from(response.data as Map);
  }
}
