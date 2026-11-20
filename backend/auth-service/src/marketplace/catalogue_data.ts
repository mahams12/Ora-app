// Generated from mobile/assets/marketplace/catalogue_v1.json — keep in sync.
// Maps listing type -> categoryId -> allowed second-level ids
// (service subcategory / rental subcategory / logistics vehicleType).
export const MARKETPLACE_TAXONOMY: Readonly<Record<string, Readonly<Record<string, readonly string[]>>>> = {
  service: {
    home_repair: ['ac', 'electrical', 'ups_generator', 'plumbing', 'geyser', 'carpentry', 'doors_windows', 'handyman', 'painting', 'flooring', 'ceiling_roof', 'renovation', 'appliance_major', 'appliance_general', 'home_inspection'],
    cleaning: ['house_cleaning', 'kitchen_bath_cleaning', 'upholstery_cleaning', 'water_tank_cleaning', 'solar_panel_cleaning', 'car_detailing', 'commercial_cleaning'],
    pest_control: ['insect_control', 'rodent_control', 'fumigation'],
    beauty: ['facial', 'makeup', 'hair', 'waxing_nails', 'mehndi', 'massage_salon'],
    solar_garden_property: ['solar_install', 'solar_inverter_battery', 'gardening', 'pool', 'water_filter', 'security_smart_home', 'fire_safety', 'construction_inspection'],
    professional: ['legal', 'accounting_tax', 'company_registration', 'digital_marketing', 'graphic_design', 'web_app_dev', 'it_support', 'data_recovery', 'photo_video', 'translation_docs', 'recruitment_hr'],
    education: ['tutoring', 'exam_prep', 'coding_training', 'music_lessons', 'driving_instruction', 'corporate_training'],
    health: ['doctor_visit', 'home_nursing', 'physiotherapy', 'lab_collection', 'medical_equipment', 'vaccination', 'dietitian', 'mental_wellness', 'dental_eye'],
    family_pet: ['childcare', 'special_needs', 'pet_care', 'vet_visit'],
    automobile: ['mobile_mechanic', 'battery_jumpstart', 'tyre_puncture', 'mobile_car_wash', 'oil_ac', 'vehicle_inspection', 'towing', 'vehicle_registration'],
    daily_life: ['laundry', 'tailoring', 'repairs_personal', 'phone_repair', 'events_catering', 'wedding_photography', 'tent_marquee', 'scrap_recycling', 'water_tanker', 'locksmith', 'security_guard'],
  },
  rental: {
    residential: ['houses', 'apartments_flats', 'studios', 'rooms_shared_rooms', 'portions'],
    vacation: ['villas', 'farmhouses', 'cottages_cabins', 'beach_houses', 'resorts'],
    hotels: ['hotel_stays', 'motels', 'guest_houses', 'hostels', 'serviced_apartments'],
    commercial: ['offices', 'shops_retail_spaces', 'showrooms', 'factories', 'warehouses'],
    events: ['wedding_halls', 'marquees', 'banquet_halls', 'party_venues', 'outdoor_event_spaces'],
    workspaces: ['coworking_spaces', 'meeting_rooms', 'conference_halls', 'training_rooms'],
    land: ['agricultural_land', 'farm_plots', 'gardens', 'private_grounds'],
    parking_storage: ['private_parking', 'garages', 'storage_units', 'storage_facilities'],
  },
  cargo: {
    bikes: ['bicycle', 'motorcycle'],
    three_wheeler: ['loader_rickshaw', 'qingqi_loader'],
    pickups: ['suzuki_ravi', 'cabin_pickup', 'small_medium_pickup', 'shehzore', 'mazda_truck'],
    vans: ['cargo_van', 'high_roof_van', 'mini_truck', 'covered_delivery_van', 'refrigerated_van', 'passenger_cargo_van'],
    trucks: ['truck_6_8_10', 'truck_12_14_16', 'heavy_duty_truck', 'open_covered_truck', 'flatbed_truck'],
    trailers: ['container_20_40', 'high_cube_container', 'flatbed_lowbed_trailer', 'extendable_skeletal_trailer', 'curtain_side_trailer', 'refrigerated_trailer', 'tanker_trailer'],
    specialized: ['dumper_tipper', 'dump_truck', 'concrete_mixer', 'mobile_crane', 'recovery_towing', 'car_carrier', 'machinery_transporter', 'water_fuel_tanker', 'livestock_refrigerated', 'garbage_vehicle'],
    freight: ['cargo_aircraft', 'cargo_helicopter', 'freight_train', 'cargo_ship', 'inland_vessel'],
  },
};
