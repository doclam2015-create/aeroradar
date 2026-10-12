import Foundation

/// Especificaciones de referencia (valores aproximados del fabricante) por código de tipo ICAO.
struct TypeSpec: Hashable {
    let name: String
    let wiki: String
    let engines: String
    let seats: String
    let rangeKm: String
    let cruise: String
    let length: String
    let span: String
    let mtow: String
    let firstFlight: String
}

enum TypeDB {
    // swiftlint:disable line_length
    private static let raw: [String: TypeSpec] = [
        "A318": .init(name: "Airbus A318", wiki: "Airbus A318", engines: "2 turbofán CFM56 / PW6000", seats: "107–132", rangeKm: "5.750", cruise: "829 km/h (M0,78)", length: "31,4 m", span: "34,1 m", mtow: "68 t", firstFlight: "2002"),
        "A319": .init(name: "Airbus A319", wiki: "Airbus A319", engines: "2 turbofán CFM56 / IAE V2500", seats: "124–156", rangeKm: "6.950", cruise: "829 km/h (M0,78)", length: "33,8 m", span: "35,8 m", mtow: "75,5 t", firstFlight: "1995"),
        "A320": .init(name: "Airbus A320", wiki: "Airbus A320", engines: "2 turbofán CFM56 / IAE V2500", seats: "150–180", rangeKm: "6.150", cruise: "829 km/h (M0,78)", length: "37,6 m", span: "35,8 m", mtow: "78 t", firstFlight: "1987"),
        "A321": .init(name: "Airbus A321", wiki: "Airbus A321", engines: "2 turbofán CFM56 / IAE V2500", seats: "185–220", rangeKm: "5.950", cruise: "829 km/h (M0,78)", length: "44,5 m", span: "35,8 m", mtow: "93,5 t", firstFlight: "1993"),
        "A19N": .init(name: "Airbus A319neo", wiki: "Airbus A320neo", engines: "2 turbofán LEAP-1A / PW1100G", seats: "120–160", rangeKm: "6.850", cruise: "833 km/h (M0,78)", length: "33,8 m", span: "35,8 m", mtow: "75,5 t", firstFlight: "2017"),
        "A20N": .init(name: "Airbus A320neo", wiki: "Airbus A320neo", engines: "2 turbofán LEAP-1A / PW1100G", seats: "165–194", rangeKm: "6.300", cruise: "833 km/h (M0,78)", length: "37,6 m", span: "35,8 m", mtow: "79 t", firstFlight: "2014"),
        "A21N": .init(name: "Airbus A321neo", wiki: "Airbus A320neo", engines: "2 turbofán LEAP-1A / PW1100G", seats: "180–244", rangeKm: "7.400", cruise: "833 km/h (M0,78)", length: "44,5 m", span: "35,8 m", mtow: "97 t", firstFlight: "2016"),
        "BCS1": .init(name: "Airbus A220-100", wiki: "Airbus A220", engines: "2 turbofán PW1500G", seats: "100–135", rangeKm: "6.390", cruise: "829 km/h (M0,78)", length: "35,0 m", span: "35,1 m", mtow: "63 t", firstFlight: "2013"),
        "BCS3": .init(name: "Airbus A220-300", wiki: "Airbus A220", engines: "2 turbofán PW1500G", seats: "120–160", rangeKm: "6.300", cruise: "829 km/h (M0,78)", length: "38,7 m", span: "35,1 m", mtow: "70,9 t", firstFlight: "2015"),
        "A306": .init(name: "Airbus A300-600", wiki: "Airbus A300", engines: "2 turbofán CF6 / PW4000", seats: "247–266", rangeKm: "7.500", cruise: "833 km/h", length: "54,1 m", span: "44,8 m", mtow: "171,7 t", firstFlight: "1983"),
        "A332": .init(name: "Airbus A330-200", wiki: "Airbus A330", engines: "2 turbofán Trent 700 / CF6 / PW4000", seats: "220–260", rangeKm: "13.450", cruise: "871 km/h (M0,82)", length: "58,8 m", span: "60,3 m", mtow: "242 t", firstFlight: "1997"),
        "A333": .init(name: "Airbus A330-300", wiki: "Airbus A330", engines: "2 turbofán Trent 700 / CF6 / PW4000", seats: "250–300", rangeKm: "11.750", cruise: "871 km/h (M0,82)", length: "63,7 m", span: "60,3 m", mtow: "242 t", firstFlight: "1992"),
        "A338": .init(name: "Airbus A330-800neo", wiki: "Airbus A330neo", engines: "2 turbofán Trent 7000", seats: "220–260", rangeKm: "15.100", cruise: "871 km/h (M0,82)", length: "58,8 m", span: "64,0 m", mtow: "251 t", firstFlight: "2018"),
        "A339": .init(name: "Airbus A330-900neo", wiki: "Airbus A330neo", engines: "2 turbofán Trent 7000", seats: "260–300", rangeKm: "13.300", cruise: "871 km/h (M0,82)", length: "63,7 m", span: "64,0 m", mtow: "251 t", firstFlight: "2017"),
        "A343": .init(name: "Airbus A340-300", wiki: "Airbus A340", engines: "4 turbofán CFM56", seats: "260–295", rangeKm: "13.500", cruise: "871 km/h (M0,82)", length: "63,7 m", span: "60,3 m", mtow: "276 t", firstFlight: "1991"),
        "A346": .init(name: "Airbus A340-600", wiki: "Airbus A340", engines: "4 turbofán Trent 500", seats: "320–370", rangeKm: "14.450", cruise: "881 km/h (M0,83)", length: "75,4 m", span: "63,5 m", mtow: "380 t", firstFlight: "2001"),
        "A359": .init(name: "Airbus A350-900", wiki: "Airbus A350", engines: "2 turbofán Trent XWB", seats: "300–350", rangeKm: "15.000", cruise: "903 km/h (M0,85)", length: "66,8 m", span: "64,8 m", mtow: "283 t", firstFlight: "2013"),
        "A35K": .init(name: "Airbus A350-1000", wiki: "Airbus A350", engines: "2 turbofán Trent XWB-97", seats: "350–410", rangeKm: "16.100", cruise: "903 km/h (M0,85)", length: "73,8 m", span: "64,8 m", mtow: "319 t", firstFlight: "2016"),
        "A388": .init(name: "Airbus A380-800", wiki: "Airbus A380", engines: "4 turbofán Trent 900 / GP7200", seats: "500–615", rangeKm: "15.000", cruise: "903 km/h (M0,85)", length: "72,7 m", span: "79,8 m", mtow: "575 t", firstFlight: "2005"),
        "B712": .init(name: "Boeing 717-200", wiki: "Boeing 717", engines: "2 turbofán BR715", seats: "106–117", rangeKm: "3.815", cruise: "811 km/h", length: "37,8 m", span: "28,4 m", mtow: "54,9 t", firstFlight: "1998"),
        "B737": .init(name: "Boeing 737-700", wiki: "Boeing 737 Next Generation", engines: "2 turbofán CFM56-7", seats: "126–149", rangeKm: "6.370", cruise: "842 km/h (M0,785)", length: "33,6 m", span: "35,8 m", mtow: "70 t", firstFlight: "1997"),
        "B738": .init(name: "Boeing 737-800", wiki: "Boeing 737 Next Generation", engines: "2 turbofán CFM56-7", seats: "162–189", rangeKm: "5.765", cruise: "842 km/h (M0,785)", length: "39,5 m", span: "35,8 m", mtow: "79 t", firstFlight: "1997"),
        "B739": .init(name: "Boeing 737-900", wiki: "Boeing 737 Next Generation", engines: "2 turbofán CFM56-7", seats: "177–220", rangeKm: "5.900", cruise: "842 km/h (M0,785)", length: "42,1 m", span: "35,8 m", mtow: "85 t", firstFlight: "2000"),
        "B37M": .init(name: "Boeing 737 MAX 7", wiki: "Boeing 737 MAX", engines: "2 turbofán LEAP-1B", seats: "138–172", rangeKm: "7.130", cruise: "839 km/h (M0,79)", length: "35,6 m", span: "35,9 m", mtow: "80 t", firstFlight: "2018"),
        "B38M": .init(name: "Boeing 737 MAX 8", wiki: "Boeing 737 MAX", engines: "2 turbofán LEAP-1B", seats: "162–210", rangeKm: "6.570", cruise: "839 km/h (M0,79)", length: "39,5 m", span: "35,9 m", mtow: "82 t", firstFlight: "2016"),
        "B39M": .init(name: "Boeing 737 MAX 9", wiki: "Boeing 737 MAX", engines: "2 turbofán LEAP-1B", seats: "178–220", rangeKm: "6.570", cruise: "839 km/h (M0,79)", length: "42,2 m", span: "35,9 m", mtow: "88 t", firstFlight: "2017"),
        "B3XM": .init(name: "Boeing 737 MAX 10", wiki: "Boeing 737 MAX", engines: "2 turbofán LEAP-1B", seats: "188–230", rangeKm: "6.110", cruise: "839 km/h (M0,79)", length: "43,8 m", span: "35,9 m", mtow: "89,8 t", firstFlight: "2021"),
        "B744": .init(name: "Boeing 747-400", wiki: "Boeing 747-400", engines: "4 turbofán CF6 / PW4000 / RB211", seats: "416–524", rangeKm: "13.450", cruise: "913 km/h (M0,85)", length: "70,6 m", span: "64,4 m", mtow: "397 t", firstFlight: "1988"),
        "B748": .init(name: "Boeing 747-8", wiki: "Boeing 747-8", engines: "4 turbofán GEnx-2B", seats: "410–467", rangeKm: "14.320", cruise: "914 km/h (M0,855)", length: "76,3 m", span: "68,4 m", mtow: "448 t", firstFlight: "2010"),
        "B752": .init(name: "Boeing 757-200", wiki: "Boeing 757", engines: "2 turbofán RB211 / PW2000", seats: "200–239", rangeKm: "7.250", cruise: "850 km/h (M0,80)", length: "47,3 m", span: "38,1 m", mtow: "116 t", firstFlight: "1982"),
        "B763": .init(name: "Boeing 767-300", wiki: "Boeing 767", engines: "2 turbofán CF6 / PW4000", seats: "218–269", rangeKm: "11.070", cruise: "851 km/h (M0,80)", length: "54,9 m", span: "47,6 m", mtow: "187 t", firstFlight: "1986"),
        "B764": .init(name: "Boeing 767-400ER", wiki: "Boeing 767", engines: "2 turbofán CF6", seats: "245–304", rangeKm: "10.415", cruise: "851 km/h (M0,80)", length: "61,4 m", span: "51,9 m", mtow: "204 t", firstFlight: "1999"),
        "B772": .init(name: "Boeing 777-200", wiki: "Boeing 777", engines: "2 turbofán GE90 / PW4000 / Trent 800", seats: "305–440", rangeKm: "9.700–13.080", cruise: "892 km/h (M0,84)", length: "63,7 m", span: "60,9 m", mtow: "247–297 t", firstFlight: "1994"),
        "B77L": .init(name: "Boeing 777-200LR", wiki: "Boeing 777", engines: "2 turbofán GE90-110B", seats: "317", rangeKm: "15.840", cruise: "892 km/h (M0,84)", length: "63,7 m", span: "64,8 m", mtow: "347 t", firstFlight: "2005"),
        "B77W": .init(name: "Boeing 777-300ER", wiki: "Boeing 777", engines: "2 turbofán GE90-115B", seats: "350–400", rangeKm: "13.650", cruise: "892 km/h (M0,84)", length: "73,9 m", span: "64,8 m", mtow: "351 t", firstFlight: "2003"),
        "B779": .init(name: "Boeing 777-9", wiki: "Boeing 777X", engines: "2 turbofán GE9X", seats: "426", rangeKm: "13.500", cruise: "905 km/h (M0,84)", length: "76,7 m", span: "71,8 m (64,8 plegadas)", mtow: "351 t", firstFlight: "2020"),
        "B788": .init(name: "Boeing 787-8 Dreamliner", wiki: "Boeing 787", engines: "2 turbofán GEnx / Trent 1000", seats: "242", rangeKm: "13.530", cruise: "903 km/h (M0,85)", length: "56,7 m", span: "60,1 m", mtow: "228 t", firstFlight: "2009"),
        "B789": .init(name: "Boeing 787-9 Dreamliner", wiki: "Boeing 787", engines: "2 turbofán GEnx / Trent 1000", seats: "290", rangeKm: "14.010", cruise: "903 km/h (M0,85)", length: "62,8 m", span: "60,1 m", mtow: "254 t", firstFlight: "2013"),
        "B78X": .init(name: "Boeing 787-10 Dreamliner", wiki: "Boeing 787", engines: "2 turbofán GEnx / Trent 1000", seats: "330", rangeKm: "11.730", cruise: "903 km/h (M0,85)", length: "68,3 m", span: "60,1 m", mtow: "254 t", firstFlight: "2017"),
        "MD11": .init(name: "McDonnell Douglas MD-11", wiki: "McDonnell Douglas MD-11", engines: "3 turbofán CF6 / PW4000", seats: "285–410", rangeKm: "12.600", cruise: "876 km/h", length: "61,6 m", span: "51,7 m", mtow: "286 t", firstFlight: "1990"),
        "E170": .init(name: "Embraer 170", wiki: "Embraer E-Jets", engines: "2 turbofán CF34-8E", seats: "70–78", rangeKm: "3.900", cruise: "870 km/h (M0,82)", length: "29,9 m", span: "26,0 m", mtow: "38,6 t", firstFlight: "2002"),
        "E75L": .init(name: "Embraer 175", wiki: "Embraer E-Jets", engines: "2 turbofán CF34-8E", seats: "76–88", rangeKm: "4.000", cruise: "870 km/h (M0,82)", length: "31,7 m", span: "26,0 m", mtow: "40,4 t", firstFlight: "2003"),
        "E75S": .init(name: "Embraer 175", wiki: "Embraer E-Jets", engines: "2 turbofán CF34-8E", seats: "76–88", rangeKm: "4.000", cruise: "870 km/h (M0,82)", length: "31,7 m", span: "26,0 m", mtow: "40,4 t", firstFlight: "2003"),
        "E190": .init(name: "Embraer 190", wiki: "Embraer E-Jets", engines: "2 turbofán CF34-10E", seats: "96–114", rangeKm: "4.500", cruise: "870 km/h (M0,82)", length: "36,2 m", span: "28,7 m", mtow: "51,8 t", firstFlight: "2004"),
        "E195": .init(name: "Embraer 195", wiki: "Embraer E-Jets", engines: "2 turbofán CF34-10E", seats: "100–124", rangeKm: "4.260", cruise: "870 km/h (M0,82)", length: "38,7 m", span: "28,7 m", mtow: "52,3 t", firstFlight: "2004"),
        "E290": .init(name: "Embraer E190-E2", wiki: "Embraer E-Jets E2", engines: "2 turbofán PW1900G", seats: "96–114", rangeKm: "5.300", cruise: "870 km/h (M0,82)", length: "36,2 m", span: "33,7 m", mtow: "56,4 t", firstFlight: "2016"),
        "E295": .init(name: "Embraer E195-E2", wiki: "Embraer E-Jets E2", engines: "2 turbofán PW1900G", seats: "120–146", rangeKm: "4.800", cruise: "870 km/h (M0,82)", length: "41,5 m", span: "35,1 m", mtow: "61,5 t", firstFlight: "2017"),
        "E145": .init(name: "Embraer ERJ-145", wiki: "Embraer ERJ 145", engines: "2 turbofán AE 3007", seats: "50", rangeKm: "2.870", cruise: "834 km/h", length: "29,9 m", span: "20,0 m", mtow: "22 t", firstFlight: "1995"),
        "CRJ2": .init(name: "Bombardier CRJ200", wiki: "Bombardier CRJ200", engines: "2 turbofán CF34-3B1", seats: "50", rangeKm: "3.045", cruise: "786 km/h", length: "26,8 m", span: "21,2 m", mtow: "24 t", firstFlight: "1991"),
        "CRJ7": .init(name: "Bombardier CRJ700", wiki: "Bombardier CRJ700", engines: "2 turbofán CF34-8C", seats: "66–78", rangeKm: "3.125", cruise: "828 km/h", length: "32,5 m", span: "23,2 m", mtow: "34 t", firstFlight: "1999"),
        "CRJ9": .init(name: "Bombardier CRJ900", wiki: "Bombardier CRJ700", engines: "2 turbofán CF34-8C", seats: "76–90", rangeKm: "2.950", cruise: "828 km/h", length: "36,2 m", span: "24,9 m", mtow: "38 t", firstFlight: "2001"),
        "AT72": .init(name: "ATR 72", wiki: "ATR 72", engines: "2 turbohélice PW127", seats: "68–78", rangeKm: "1.500", cruise: "510 km/h", length: "27,2 m", span: "27,1 m", mtow: "23 t", firstFlight: "1988"),
        "AT76": .init(name: "ATR 72-600", wiki: "ATR 72", engines: "2 turbohélice PW127M", seats: "68–78", rangeKm: "1.500", cruise: "510 km/h", length: "27,2 m", span: "27,1 m", mtow: "23 t", firstFlight: "2009"),
        "AT45": .init(name: "ATR 42-500", wiki: "ATR 42", engines: "2 turbohélice PW127", seats: "48–50", rangeKm: "1.300", cruise: "535 km/h", length: "22,7 m", span: "24,6 m", mtow: "18,6 t", firstFlight: "1984"),
        "AT46": .init(name: "ATR 42-600", wiki: "ATR 42", engines: "2 turbohélice PW127M", seats: "48–50", rangeKm: "1.300", cruise: "535 km/h", length: "22,7 m", span: "24,6 m", mtow: "18,6 t", firstFlight: "2010"),
        "DH8D": .init(name: "De Havilland Dash 8-400", wiki: "Bombardier Dash 8", engines: "2 turbohélice PW150A", seats: "68–90", rangeKm: "2.040", cruise: "667 km/h", length: "32,8 m", span: "28,4 m", mtow: "29,6 t", firstFlight: "1998"),
        "SU95": .init(name: "Sukhoi Superjet 100", wiki: "Sukhoi Superjet 100", engines: "2 turbofán SaM146", seats: "87–108", rangeKm: "3.000–4.500", cruise: "828 km/h", length: "29,9 m", span: "27,8 m", mtow: "49,5 t", firstFlight: "2008"),
        "C919": .init(name: "COMAC C919", wiki: "COMAC C919", engines: "2 turbofán LEAP-1C", seats: "158–192", rangeKm: "4.075–5.555", cruise: "834 km/h", length: "38,9 m", span: "35,8 m", mtow: "77,3 t", firstFlight: "2017"),
        "A124": .init(name: "Antonov An-124 Ruslan", wiki: "Antonov An-124", engines: "4 turbofán D-18T", seats: "Carga (120 t)", rangeKm: "4.800 con 120 t", cruise: "800–850 km/h", length: "69,0 m", span: "73,3 m", mtow: "402 t", firstFlight: "1982"),
        "C172": .init(name: "Cessna 172 Skyhawk", wiki: "Cessna 172", engines: "1 motor de pistón Lycoming", seats: "4", rangeKm: "1.185", cruise: "226 km/h", length: "8,3 m", span: "11,0 m", mtow: "1,1 t", firstFlight: "1955"),
        "C152": .init(name: "Cessna 152", wiki: "Cessna 152", engines: "1 motor de pistón Lycoming", seats: "2", rangeKm: "770", cruise: "198 km/h", length: "7,3 m", span: "10,2 m", mtow: "0,76 t", firstFlight: "1977"),
        "P28A": .init(name: "Piper PA-28 Cherokee", wiki: "Piper PA-28 Cherokee", engines: "1 motor de pistón Lycoming", seats: "4", rangeKm: "1.000", cruise: "220 km/h", length: "7,3 m", span: "10,7 m", mtow: "1,1 t", firstFlight: "1960"),
        "C208": .init(name: "Cessna 208 Caravan", wiki: "Cessna 208 Caravan", engines: "1 turbohélice PT6A", seats: "9–14", rangeKm: "1.980", cruise: "344 km/h", length: "11,5 m", span: "15,9 m", mtow: "3,97 t", firstFlight: "1982"),
        "PC12": .init(name: "Pilatus PC-12", wiki: "Pilatus PC-12", engines: "1 turbohélice PT6A-67", seats: "6–9", rangeKm: "3.417", cruise: "528 km/h", length: "14,4 m", span: "16,3 m", mtow: "4,74 t", firstFlight: "1991"),
        "B350": .init(name: "Beechcraft King Air 350", wiki: "Beechcraft Super King Air", engines: "2 turbohélice PT6A-60A", seats: "8–11", rangeKm: "3.345", cruise: "578 km/h", length: "14,2 m", span: "17,7 m", mtow: "6,8 t", firstFlight: "1988"),
        "B200": .init(name: "Beechcraft King Air 200", wiki: "Beechcraft Super King Air", engines: "2 turbohélice PT6A-42", seats: "7–9", rangeKm: "3.338", cruise: "536 km/h", length: "13,3 m", span: "16,6 m", mtow: "5,7 t", firstFlight: "1972"),
        "C68A": .init(name: "Cessna Citation Latitude", wiki: "Cessna Citation Latitude", engines: "2 turbofán PW306D", seats: "9", rangeKm: "5.000", cruise: "826 km/h", length: "19,0 m", span: "22,0 m", mtow: "14 t", firstFlight: "2014"),
        "GLF6": .init(name: "Gulfstream G650", wiki: "Gulfstream G650", engines: "2 turbofán BR725", seats: "11–19", rangeKm: "13.890", cruise: "956 km/h (M0,90)", length: "30,4 m", span: "30,4 m", mtow: "45,2 t", firstFlight: "2009"),
        "GLEX": .init(name: "Bombardier Global Express", wiki: "Bombardier Global Express", engines: "2 turbofán BR710", seats: "13–19", rangeKm: "11.100", cruise: "904 km/h (M0,85)", length: "30,3 m", span: "28,7 m", mtow: "45 t", firstFlight: "1996"),
        "LJ45": .init(name: "Learjet 45", wiki: "Learjet 45", engines: "2 turbofán TFE731-20", seats: "8–9", rangeKm: "3.650", cruise: "850 km/h", length: "17,7 m", span: "14,6 m", mtow: "9,75 t", firstFlight: "1995"),
        "C130": .init(name: "Lockheed C-130 Hercules", wiki: "Lockheed C-130 Hercules", engines: "4 turbohélice T56", seats: "92 soldados / carga 19 t", rangeKm: "3.800", cruise: "540 km/h", length: "29,8 m", span: "40,4 m", mtow: "70,3 t", firstFlight: "1954"),
        "C30J": .init(name: "Lockheed Martin C-130J Super Hercules", wiki: "Lockheed C-130 Hercules", engines: "4 turbohélice AE 2100D3", seats: "92 soldados / carga 19 t", rangeKm: "3.300", cruise: "643 km/h", length: "29,8 m", span: "40,4 m", mtow: "70,3 t", firstFlight: "1996"),
        "A400": .init(name: "Airbus A400M Atlas", wiki: "Airbus A400M", engines: "4 turbohélice TP400-D6", seats: "116 soldados / carga 37 t", rangeKm: "3.300 con 37 t", cruise: "781 km/h", length: "45,1 m", span: "42,4 m", mtow: "141 t", firstFlight: "2009"),
        "K35R": .init(name: "Boeing KC-135 Stratotanker", wiki: "Boeing KC-135 Stratotanker", engines: "4 turbofán CFM56 (F108)", seats: "Avión cisterna", rangeKm: "2.400 con carga", cruise: "853 km/h", length: "41,5 m", span: "39,9 m", mtow: "146 t", firstFlight: "1956"),
        "C17": .init(name: "Boeing C-17 Globemaster III", wiki: "Boeing C-17 Globemaster III", engines: "4 turbofán F117", seats: "102 paracaidistas / carga 77 t", rangeKm: "4.480", cruise: "830 km/h", length: "53,0 m", span: "51,8 m", mtow: "265 t", firstFlight: "1991"),
        "F16": .init(name: "Lockheed Martin F-16 Fighting Falcon", wiki: "General Dynamics F-16 Fighting Falcon", engines: "1 turbofán F110 / F100", seats: "1–2", rangeKm: "4.220 (traslado)", cruise: "Máx. Mach 2", length: "15,1 m", span: "9,96 m", mtow: "19,2 t", firstFlight: "1974"),
        "E314": .init(name: "Embraer A-29 Super Tucano", wiki: "Embraer EMB 314 Super Tucano", engines: "1 turbohélice PT6A-68C", seats: "1–2", rangeKm: "1.330", cruise: "520 km/h", length: "11,4 m", span: "11,1 m", mtow: "5,4 t", firstFlight: "1999"),
        "EC35": .init(name: "Airbus H135 (EC135)", wiki: "Eurocopter EC135", engines: "2 turboejes PW206B / Arrius 2B", seats: "1 piloto + 6–7", rangeKm: "635", cruise: "254 km/h", length: "12,2 m", span: "Rotor 10,2 m", mtow: "2,98 t", firstFlight: "1994"),
        "EC45": .init(name: "Airbus H145 (EC145)", wiki: "Airbus Helicopters H145", engines: "2 turboejes Arriel 2E", seats: "1–2 pilotos + 9", rangeKm: "650", cruise: "246 km/h", length: "13,6 m", span: "Rotor 11,0 m", mtow: "3,8 t", firstFlight: "1999"),
        "A139": .init(name: "Leonardo AW139", wiki: "AgustaWestland AW139", engines: "2 turboejes PT6C-67C", seats: "2 pilotos + 15", rangeKm: "1.060", cruise: "306 km/h", length: "16,7 m", span: "Rotor 13,8 m", mtow: "7 t", firstFlight: "2001"),
        "B06": .init(name: "Bell 206 JetRanger", wiki: "Bell 206", engines: "1 turboeje Allison 250", seats: "4–5", rangeKm: "693", cruise: "213 km/h", length: "11,9 m", span: "Rotor 10,2 m", mtow: "1,45 t", firstFlight: "1966"),
        "B412": .init(name: "Bell 412", wiki: "Bell 412", engines: "2 turboejes PT6T-3", seats: "1–2 pilotos + 13", rangeKm: "745", cruise: "226 km/h", length: "17,1 m", span: "Rotor 14,0 m", mtow: "5,4 t", firstFlight: "1979"),
        "H60": .init(name: "Sikorsky UH-60 Black Hawk", wiki: "Sikorsky UH-60 Black Hawk", engines: "2 turboejes T700", seats: "2 pilotos + 11–14", rangeKm: "590", cruise: "280 km/h", length: "19,8 m", span: "Rotor 16,4 m", mtow: "10,7 t", firstFlight: "1974"),
        "R44": .init(name: "Robinson R44", wiki: "Robinson R44", engines: "1 motor de pistón Lycoming", seats: "4", rangeKm: "560", cruise: "200 km/h", length: "11,7 m", span: "Rotor 10,1 m", mtow: "1,13 t", firstFlight: "1990"),
    ]
    // swiftlint:enable line_length

    static func spec(for code: String?) -> TypeSpec? {
        guard let c = code?.uppercased() else { return nil }
        return raw[c]
    }
}
