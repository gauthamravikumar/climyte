import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #file, line: Int = #line) {
    if actual != expected {
        print("❌ Test failed [\(file):\(line)]: expected \(expected), got \(actual). \(message)")
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String = "", file: String = #file, line: Int = #line) {
    if !condition {
        print("❌ Test failed [\(file):\(line)]: expected true condition. \(message)")
        exit(1)
    }
}

@main
struct ViewModelTestRunner {
    static func main() async {
        print("Starting WeatherViewModel tests...")
        await testDefaultInitialization()
        await testSelectCity()
        await testUserDefaultsPersistence()
        print("✅ All WeatherViewModel tests passed!")
    }
    
    @MainActor
    static func testDefaultInitialization() async {
        let key = "saved_active_city"
        UserDefaults.standard.removeObject(forKey: key)
        
        let vm = WeatherViewModel()
        assertEqual(vm.activeCity.name, "Sydney", "Default active city should be Sydney")
        assertEqual(vm.activeCity.country, "Australia", "Default country should be Australia")
        print("  ✓ testDefaultInitialization passed")
    }
    
    @MainActor
    static func testSelectCity() async {
        let vm = WeatherViewModel()
        vm.searchQuery = "Tokyo"
        vm.searchResults = [GeocodingResult(id: 1, name: "Tokyo", latitude: 35.6762, longitude: 139.6503, country: "Japan", admin1: "Tokyo")]
        
        let result = GeocodingResult(id: 1, name: "Tokyo", latitude: 35.6762, longitude: 139.6503, country: "Japan", admin1: "Tokyo")
        vm.selectCity(result)
        
        assertEqual(vm.activeCity.name, "Tokyo", "Active city name should update to Tokyo")
        assertEqual(vm.activeCity.country, "Japan", "Active city country should update to Japan")
        assertEqual(vm.activeCity.latitude, 35.6762, "Active city latitude should match result")
        assertEqual(vm.activeCity.longitude, 139.6503, "Active city longitude should match result")
        assertEqual(vm.searchQuery, "", "searchQuery should be cleared")
        assertTrue(vm.searchResults.isEmpty, "searchResults should be cleared")
        
        print("  ✓ testSelectCity passed")
    }
    
    @MainActor
    static func testUserDefaultsPersistence() async {
        let key = "saved_active_city"
        let customCity = City(id: UUID(), name: "Paris", country: "France", latitude: 48.8566, longitude: 2.3522)
        if let encoded = try? JSONEncoder().encode(customCity) {
            UserDefaults.standard.set(encoded, forKey: key)
        }
        
        let vm = WeatherViewModel()
        assertEqual(vm.activeCity.name, "Paris", "Active city loaded from UserDefaults should be Paris")
        assertEqual(vm.activeCity.country, "France", "Loaded country should be France")
        
        // Clean up key
        UserDefaults.standard.removeObject(forKey: key)
        print("  ✓ testUserDefaultsPersistence passed")
    }
}
