import 'package:flutter/material.dart';

const Map<String, IconData> categoriaIcones = {
  'fitness_center': Icons.fitness_center_rounded,
  'bolt': Icons.bolt_rounded,
  'local_fire_department': Icons.local_fire_department_rounded,
  'accessibility': Icons.accessibility_rounded,
  'directions_run': Icons.directions_run_rounded,
  'self_improvement': Icons.self_improvement_rounded,
  'spa': Icons.spa_rounded,
  'checkroom': Icons.checkroom_rounded,
  'shopping_bag': Icons.shopping_bag,
  'styler': Icons.style,
  'dry_cleaning': Icons.dry_cleaning_rounded,
  'watch': Icons.watch_rounded,
  'sports_bar': Icons.sports_bar_rounded,
  'restaurant': Icons.restaurant_rounded,
  'local_pharmacy': Icons.local_pharmacy_rounded,
  'medical_services': Icons.medical_services_rounded,
  'health_and_safety': Icons.health_and_safety_rounded,
  'eco': Icons.eco_rounded,
  'pets': Icons.pets_rounded,
  'shield': Icons.shield_rounded,
  'star': Icons.star_rounded,
  'thumb_up': Icons.thumb_up_rounded,
  'local_mall': Icons.local_mall_rounded,
  'inventory_2': Icons.inventory_2_rounded,
  'category': Icons.category_rounded,
  'label': Icons.label_rounded,
  'card_giftcard': Icons.card_giftcard_rounded,
  'percent': Icons.percent,
  'local_offer': Icons.local_offer_rounded,
  'storefront': Icons.storefront_rounded,
  'shopping_cart': Icons.shopping_cart_rounded,
  'playlist_add': Icons.playlist_add_rounded,
  'edit': Icons.edit_rounded,
  'visibility': Icons.visibility_rounded,
  'favorite': Icons.favorite_rounded,
  'alarm': Icons.alarm_rounded,
  'timer': Icons.timer_rounded,
  'flag': Icons.flag_rounded,
  'bookmark': Icons.bookmark_rounded,
  'home': Icons.home_rounded,
  'monitor_heart': Icons.monitor_heart_rounded,
  'scale': Icons.scale_rounded,
  'egg': Icons.egg_rounded,
  'coffee': Icons.coffee_rounded,
  'water_drop': Icons.water_drop_rounded,
  'lunch_dining': Icons.lunch_dining_rounded,
  'bakery_dining': Icons.bakery_dining_rounded,
  'dinner_dining': Icons.dinner_dining_rounded,
  'brunch_dining': Icons.brunch_dining_rounded,
  'takeout_dining': Icons.takeout_dining_rounded,
  'icecream': Icons.icecream_rounded,
  'outdoor_grill': Icons.outdoor_grill_rounded,
  'kitchen': Icons.kitchen_rounded,
  'microwave': Icons.microwave_rounded,
  'wb_sunny': Icons.wb_sunny_rounded,
  'cloud': Icons.cloud_rounded,
  'landscape': Icons.landscape_rounded,
  'terrain': Icons.terrain_rounded,
  'waves': Icons.waves_rounded,
  'pool': Icons.pool_rounded,
  'air': Icons.air_rounded,
  'ac_unit': Icons.ac_unit_rounded,
  'chair': Icons.chair_rounded,
  'bed': Icons.bed_rounded,
  'weekend': Icons.weekend_rounded,
  'deck': Icons.deck_rounded,
  'grass': Icons.grass_rounded,
  'yard': Icons.yard_rounded,
  'monitor_weight': Icons.monitor_weight_rounded,
};

IconData resolverIconeCategoria(String? iconKey, String nome) {
  if (iconKey != null && categoriaIcones.containsKey(iconKey)) {
    return categoriaIcones[iconKey]!;
  }
  switch (nome.toLowerCase()) {
    case 'proteínas':
    case 'proteinas':
    case 'proteína':
    case 'proteina':
    case 'whey':
      return Icons.inventory_2_rounded;
    case 'creatina':
      return Icons.energy_savings_leaf_rounded;
    case 'hipercalóricos':
    case 'hipercaloricos':
    case 'mass gainer':
      return Icons.monitor_heart_outlined;
    case 'pré-treino':
    case 'pre-treino':
    case 'pre treino':
      return Icons.local_fire_department_rounded;
    case 'roupas':
    case 'roupa':
      return Icons.checkroom_rounded;
    case 'equipamentos':
    case 'equipamento':
      return Icons.inventory_2_rounded;
    case 'naturais':
    case 'natural':
      return Icons.eco_rounded;
    case 'vitaminas':
    case 'vitamina':
      return Icons.medication_rounded;
    case 'saúde & bem-estar':
    case 'saude & bem-estar':
    case 'saude e bem-estar':
    case 'bem-estar':
      return Icons.health_and_safety_rounded;
    case 'acessórios':
    case 'acessorios':
      return Icons.watch_rounded;
    case 'alongamento & yoga':
    case 'yoga':
    case 'alongamento':
      return Icons.self_improvement_rounded;
    case 'emagrecimento':
      return Icons.monitor_weight_rounded;
    case 'ofertas especiais':
    case 'ofertas':
      return Icons.local_offer_rounded;
    case 'snacks':
    case 'lanches':
      return Icons.lunch_dining_rounded;
    case 'termo':
    case 'termogênico':
    case 'termogenicos':
      return Icons.local_fire_department_rounded;
    case 'amino':
    case 'aminoácidos':
    case 'aminoacidos':
      return Icons.bolt_rounded;
    case 'masculino':
      return Icons.male_rounded;
    case 'feminino':
      return Icons.female_rounded;
    default:
      return Icons.storefront_rounded;
  }
}
