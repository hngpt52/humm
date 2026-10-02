import Foundation

/// Turns American spellings into British ones after transcription: both models write American
/// spelling whatever the prompt says (tested: 0 of 17 British spellings with a British English
/// prompt). Whole words from a fixed list, keeping capitals. Words whose spelling depends on the
/// meaning are left alone: program (code), practice, license, meter, check, tire, dialog.
enum BritishSpelling {
    static func convert(_ text: String) -> String { convertCounting(text).text }

    /// The text in British spelling, and how many words changed (see Insights).
    static func convertCounting(_ text: String) -> (text: String, count: Int) {
        let words = text as NSString
        var result = ""
        var last = 0
        var count = 0
        for match in wordPattern.matches(in: text, range: NSRange(location: 0, length: words.length)) {
            let word = words.substring(with: match.range)
            guard let british = table[word.lowercased()] else { continue }
            result += words.substring(with: NSRange(location: last, length: match.range.location - last))
            result += matchCase(british, to: word)
            last = NSMaxRange(match.range)
            count += 1
        }
        return (last == 0 ? text : result + words.substring(from: last), count)
    }

    private static let wordPattern = try! NSRegularExpression(pattern: "[A-Za-z]+")

    private static func matchCase(_ british: String, to american: String) -> String {
        if american == american.uppercased(), american.count > 1 { return british.uppercased() }
        if american.first?.isUppercase == true { return british.prefix(1).uppercased() + british.dropFirst() }
        return british
    }

    /// American (lower case) to British.
    private static let table: [String: String] = {
        var table: [String: String] = [:]
        // -ize and -yze verbs, with their inflections and nouns: organize, organized, organization.
        for stem in izeStems {
            for (american, british) in [("ize", "ise"), ("izes", "ises"), ("ized", "ised"), ("izing", "ising"),
                                        ("ization", "isation"), ("izations", "isations"), ("izer", "iser"), ("izers", "isers")] {
                table[stem + american] = stem + british
            }
        }
        for stem in ["analy", "paraly", "cataly", "hydroly", "electroly", "dialy"] {
            for (american, british) in [("ze", "se"), ("zes", "ses"), ("zed", "sed"), ("zing", "sing"), ("zer", "ser"), ("zers", "sers")] {
                table[stem + american] = stem + british
            }
        }
        // -or to -our: colour, favourite, neighbourhood (the first "or" becomes "our").
        for american in orWords {
            if let range = american.range(of: "or") {
                table[american] = american.replacingCharacters(in: range, with: "our")
            }
        }
        for (american, british) in pairs { table[american] = british }
        return table
    }()

    /// Stems of -ize verbs spelt -ise in British English. Not size, seize, prize, capsize or
    /// resize, which keep their z.
    private static let izeStems = [
        "accessor", "actual", "agon", "apolog", "author", "bapt", "brutal", "capital", "categor", "central",
        "character", "civil", "colon", "commercial", "computer", "critic", "custom", "decentral", "demoral", "desensit",
        "digit", "dramat", "econom", "emphas", "energ", "equal", "familiar", "fantas", "fertil", "final", "formal",
        "fossil", "general", "global", "harmon", "hospital", "hypothes", "ideal", "immun", "individual", "industrial",
        "initial", "institutional", "internal", "international", "italic", "jeopard", "legal", "legitim", "liberal", "local",
        "marginal", "material", "maxim", "mechan", "memor", "mesmer", "metabol", "minim", "mobil", "modern", "moistur",
        "monet", "monopol", "moral", "national", "natural", "neutral", "normal", "optim", "organ", "ostrac", "oxid",
        "patron", "penal", "personal", "philosoph", "plagiar", "polar", "popular", "pressur", "priorit", "privat",
        "public", "rational", "real", "recogn", "reorgan", "revolution", "romantic", "sanit", "scrutin", "sensit",
        "sermon", "social", "special", "stabil", "standard", "steril", "stigmat", "strateg", "subsid", "summar",
        "symbol", "sympath", "synchron", "synthes", "tantal", "terror", "theor", "trivial", "union",
        "urban", "util", "vapor", "verbal", "victim", "visual", "vocal", "western",
    ]

    /// American -or words spelt -our in British English. Not humorous, laborious or glamorous.
    private static let orWords = [
        "ardor", "armor", "armored", "armory", "behavior", "behavioral", "behaviors", "candor", "clamor", "color",
        "colored", "colorful", "colorfully", "coloring", "colorless", "colors", "demeanor", "discolor", "discolored",
        "dishonor", "endeavor", "endeavored", "endeavoring", "endeavors", "favor", "favorable", "favorably", "favored",
        "favoring", "favorite", "favorites", "favoritism", "favors", "fervor", "flavor", "flavored", "flavorful",
        "flavoring", "flavors", "glamor", "harbor", "harbored", "harbors", "honor", "honorable", "honorably", "honored",
        "honoring", "honors", "humor", "humored", "humoring", "humors", "labor", "labored", "laborer", "laborers",
        "laboring", "labors", "misbehavior", "neighbor", "neighborhood", "neighborhoods", "neighboring", "neighborly",
        "neighbors", "odor", "odors", "parlor", "rigor", "rumor", "rumored", "rumors", "savor", "savory", "splendor",
        "tumor", "tumors", "unfavorable", "valor", "vapor", "vapors", "vigor",
    ]

    private static let pairs: [(String, String)] = [
        // -er to -re
        ("center", "centre"), ("centers", "centres"), ("centered", "centred"), ("centering", "centring"),
        ("theater", "theatre"), ("theaters", "theatres"), ("fiber", "fibre"), ("fibers", "fibres"),
        ("liter", "litre"), ("liters", "litres"), ("caliber", "calibre"), ("saber", "sabre"), ("somber", "sombre"),
        ("specter", "spectre"), ("luster", "lustre"), ("meager", "meagre"), ("sepulcher", "sepulchre"),
        ("kilometer", "kilometre"), ("kilometers", "kilometres"), ("centimeter", "centimetre"), ("centimeters", "centimetres"),
        ("millimeter", "millimetre"), ("millimeters", "millimetres"), ("milliliter", "millilitre"), ("milliliters", "millilitres"),
        ("maneuver", "manoeuvre"), ("maneuvers", "manoeuvres"), ("maneuvered", "manoeuvred"), ("maneuvering", "manoeuvring"),
        // doubled l
        ("traveler", "traveller"), ("travelers", "travellers"), ("traveled", "travelled"), ("traveling", "travelling"),
        ("canceled", "cancelled"), ("canceling", "cancelling"), ("labeled", "labelled"), ("labeling", "labelling"),
        ("modeled", "modelled"), ("modeling", "modelling"), ("fueled", "fuelled"), ("fueling", "fuelling"),
        ("leveled", "levelled"), ("leveling", "levelling"), ("signaled", "signalled"), ("signaling", "signalling"),
        ("totaled", "totalled"), ("totaling", "totalling"), ("dialed", "dialled"), ("dialing", "dialling"),
        ("quarreled", "quarrelled"), ("quarreling", "quarrelling"), ("equaled", "equalled"), ("equaling", "equalling"),
        ("rivaled", "rivalled"), ("tunneled", "tunnelled"), ("channeled", "channelled"), ("funneled", "funnelled"),
        ("marveled", "marvelled"), ("marvelous", "marvellous"), ("counselor", "counsellor"), ("counselors", "counsellors"),
        ("counseled", "counselled"), ("counseling", "counselling"), ("jeweler", "jeweller"), ("jewelers", "jewellers"),
        ("jewelry", "jewellery"), ("woolen", "woollen"), ("enrollment", "enrolment"), ("fulfill", "fulfil"),
        ("fulfillment", "fulfilment"), ("skillful", "skilful"), ("willful", "wilful"), ("installment", "instalment"),
        // -og to -ogue, -ense to -ence
        ("catalog", "catalogue"), ("catalogs", "catalogues"), ("cataloged", "catalogued"), ("analog", "analogue"),
        ("monolog", "monologue"), ("prolog", "prologue"), ("epilog", "epilogue"),
        ("defense", "defence"), ("defenses", "defences"), ("offense", "offence"), ("offenses", "offences"),
        ("pretense", "pretence"),
        // other
        ("gray", "grey"), ("grays", "greys"), ("grayish", "greyish"), ("aluminum", "aluminium"),
        ("airplane", "aeroplane"), ("airplanes", "aeroplanes"), ("pajamas", "pyjamas"), ("plow", "plough"),
        ("mold", "mould"), ("molds", "moulds"), ("moldy", "mouldy"), ("mustache", "moustache"), ("cozy", "cosy"),
        ("artifact", "artefact"), ("artifacts", "artefacts"), ("judgment", "judgement"), ("judgments", "judgements"),
        ("acknowledgment", "acknowledgement"), ("acknowledgments", "acknowledgements"), ("aging", "ageing"),
        ("yogurt", "yoghurt"), ("esthetic", "aesthetic"), ("practicing", "practising"), ("practiced", "practised"),
        ("tidbit", "titbit"), ("sulfur", "sulphur"),
    ]
}
