import Foundation

struct DemoRecipeScenario: Hashable {
    struct Ingredient: Hashable {
        let amount: String
        let unit: String
        let name: String
    }

    struct Hero: Hashable {
        let emoji: String
        let topColorHex: UInt
        let bottomColorHex: UInt
        let accentColorHex: UInt
    }

    let id: String
    let matchGroups: [[String]]
    let title: String
    let summary: String
    let servings: String
    let prepMinutes: Int
    let cookMinutes: Int
    let hero: Hero
    let ingredients: [Ingredient]
    let steps: [String]
}

enum DemoRecipeCatalog {
    // Keep the most specific scenarios first so the matcher stays predictable.
    static let scenarios: [DemoRecipeScenario] = [
        DemoRecipeScenario(
            id: "nuggets-pasta",
            matchGroups: [
                ["nuggets", "nugget", "tenders", "crispy chicken", "nuggetspasta"],
                ["pasta", "pates", "macaroni", "penne", "mac cheese", "creamypasta"]
            ],
            title: "Nuggets croustillants & pates cremeuses",
            summary: "Un combo ultra comfort food pense pour une demo TikTok tres gourmande.",
            servings: "2",
            prepMinutes: 15,
            cookMinutes: 20,
            hero: .init(emoji: "🍗", topColorHex: 0xF58A2A, bottomColorHex: 0xF7C95C, accentColorHex: 0xFFF4D0),
            ingredients: [
                .init(amount: "250", unit: "g", name: "nuggets de poulet"),
                .init(amount: "220", unit: "g", name: "pates courtes"),
                .init(amount: "120", unit: "ml", name: "creme entiere"),
                .init(amount: "40", unit: "g", name: "parmesan rape"),
                .init(amount: "1", unit: "c. a soupe", name: "beurre"),
                .init(amount: "1", unit: "", name: "gousse d'ail"),
                .init(amount: "1", unit: "poignee", name: "persil"),
                .init(amount: "", unit: "", name: "poivre noir")
            ],
            steps: [
                "Faites cuire les nuggets jusqu'a ce qu'ils soient bien dores et croustillants.",
                "Pendant ce temps, faites cuire les pates dans une eau bien salee puis gardez une petite louche d'eau de cuisson.",
                "Faites revenir l'ail dans le beurre, ajoutez la creme puis le parmesan pour obtenir une sauce lisse.",
                "Melez les pates a la sauce avec un peu d'eau de cuisson pour la rendre brillante.",
                "Servez les pates cremeuses avec les nuggets dessus, du persil et un tour de poivre."
            ]
        ),
        DemoRecipeScenario(
            id: "chicken-wrap",
            matchGroups: [
                ["wrap", "wraps", "tortilla", "roll up", "chickenwrap"],
                ["chicken", "poulet", "crispy chicken", "grilled chicken"]
            ],
            title: "Wrap poulet croustillant sauce maison",
            summary: "Le wrap poulet rapide qui marche parfaitement pour une demo mobile tres clean.",
            servings: "2",
            prepMinutes: 12,
            cookMinutes: 10,
            hero: .init(emoji: "🌯", topColorHex: 0xE08642, bottomColorHex: 0xF4D07D, accentColorHex: 0xFFF6E2),
            ingredients: [
                .init(amount: "2", unit: "", name: "grandes tortillas"),
                .init(amount: "220", unit: "g", name: "poulet croustillant"),
                .init(amount: "1", unit: "petite", name: "laitue eminces"),
                .init(amount: "1", unit: "", name: "tomate"),
                .init(amount: "1/2", unit: "", name: "avocat"),
                .init(amount: "3", unit: "c. a soupe", name: "yaourt grec"),
                .init(amount: "1", unit: "c. a cafe", name: "paprika"),
                .init(amount: "1", unit: "trait", name: "jus de citron")
            ],
            steps: [
                "Melangez le yaourt grec, le paprika et le citron pour preparer une sauce fraiche.",
                "Rechauffez les tortillas quelques secondes pour qu'elles soient souples.",
                "Garnissez chaque tortilla avec la laitue, la tomate, l'avocat et le poulet croustillant.",
                "Ajoutez la sauce, repliez les cotes puis roulez bien serre.",
                "Coupez en deux et servez aussitot."
            ]
        ),
        DemoRecipeScenario(
            id: "salmon-rice-bowl",
            matchGroups: [
                ["salmon", "saumon", "salmonricebowl"],
                ["rice", "riz", "rice bowl", "bowl"]
            ],
            title: "Salmon rice bowl croustillant",
            summary: "Un bowl saumon riz tres moderne, parfait pour une recette visuelle et premium.",
            servings: "2",
            prepMinutes: 15,
            cookMinutes: 18,
            hero: .init(emoji: "🍣", topColorHex: 0xF46D5B, bottomColorHex: 0xF7B267, accentColorHex: 0xFFF1DF),
            ingredients: [
                .init(amount: "2", unit: "", name: "filets de saumon"),
                .init(amount: "180", unit: "g", name: "riz a sushi"),
                .init(amount: "1", unit: "", name: "concombre"),
                .init(amount: "1/2", unit: "", name: "avocat"),
                .init(amount: "2", unit: "c. a soupe", name: "sauce soja"),
                .init(amount: "1", unit: "c. a soupe", name: "miel"),
                .init(amount: "1", unit: "c. a cafe", name: "huile de sesame"),
                .init(amount: "1", unit: "c. a soupe", name: "graines de sesame")
            ],
            steps: [
                "Faites cuire le riz puis laissez-le tiedir pendant que vous preparez le reste.",
                "Badigeonnez le saumon avec la sauce soja, le miel et l'huile de sesame.",
                "Poelez ou enfournez le saumon jusqu'a ce qu'il soit dore a l'exterieur et nacre a coeur.",
                "Coupez le concombre et l'avocat en fines tranches puis disposez-les sur le riz.",
                "Ajoutez le saumon en morceaux, parsemez de sesame et servez avec un filet de sauce soja."
            ]
        ),
        DemoRecipeScenario(
            id: "creamy-pasta",
            matchGroups: [
                ["creamy", "creamy pasta", "cremeuse", "cremeux", "alfredo", "creamypasta"],
                ["pasta", "pates", "spaghetti", "rigatoni", "fettuccine", "penne"]
            ],
            title: "Pates cremeuses a l'ail et au parmesan",
            summary: "Une assiette de pates tres glossy pour un import demo qui donne faim instantanement.",
            servings: "2",
            prepMinutes: 10,
            cookMinutes: 15,
            hero: .init(emoji: "🍝", topColorHex: 0xF1B24A, bottomColorHex: 0xF6E3A1, accentColorHex: 0xFFF6D8),
            ingredients: [
                .init(amount: "220", unit: "g", name: "rigatoni"),
                .init(amount: "150", unit: "ml", name: "creme liquide"),
                .init(amount: "45", unit: "g", name: "parmesan"),
                .init(amount: "1", unit: "c. a soupe", name: "beurre"),
                .init(amount: "2", unit: "", name: "gousses d'ail"),
                .init(amount: "1", unit: "poignee", name: "epinards"),
                .init(amount: "", unit: "", name: "poivre noir")
            ],
            steps: [
                "Faites cuire les pates al dente et gardez un peu d'eau de cuisson.",
                "Faites fondre le beurre puis revenez l'ail quelques secondes sans le colorer.",
                "Versez la creme, ajoutez le parmesan et fouettez jusqu'a obtenir une sauce onctueuse.",
                "Ajoutez les pates et les epinards, puis detendez avec un peu d'eau de cuisson.",
                "Servez avec encore un peu de parmesan et beaucoup de poivre."
            ]
        ),
        DemoRecipeScenario(
            id: "overnight-oats",
            matchGroups: [
                ["overnight oats", "overnight", "overnightoats", "oats", "avoine"]
            ],
            title: "Overnight oats vanille fruits rouges",
            summary: "Le petit-dejeuner prep-ahead qui marche tres bien en demo sante et meal prep.",
            servings: "1",
            prepMinutes: 8,
            cookMinutes: 0,
            hero: .init(emoji: "🥣", topColorHex: 0xD45A4A, bottomColorHex: 0xF0B25C, accentColorHex: 0xFFF1E2),
            ingredients: [
                .init(amount: "60", unit: "g", name: "flocons d'avoine"),
                .init(amount: "120", unit: "ml", name: "lait d'amande"),
                .init(amount: "80", unit: "g", name: "yaourt grec"),
                .init(amount: "1", unit: "c. a soupe", name: "graines de chia"),
                .init(amount: "1", unit: "c. a cafe", name: "sirop d'erable"),
                .init(amount: "1", unit: "poignee", name: "fruits rouges"),
                .init(amount: "1", unit: "c. a soupe", name: "amandes concassees")
            ],
            steps: [
                "Melangez les flocons d'avoine, le lait d'amande, le yaourt, les graines de chia et le sirop d'erable.",
                "Versez dans un bocal et laissez reposer au frais toute la nuit.",
                "Le lendemain, ajoutez les fruits rouges et les amandes juste avant de servir.",
                "Degustez bien froid pour une texture ultra cremeuse."
            ]
        ),
        DemoRecipeScenario(
            id: "vodka-pasta",
            matchGroups: [
                ["vodka", "vodkapasta"],
                ["pasta", "pates", "rigatoni", "penne"]
            ],
            title: "Vodka pasta tomate pimentee",
            summary: "La recette viral pasta facile a reconnaitre dans un flux TikTok food.",
            servings: "2",
            prepMinutes: 12,
            cookMinutes: 18,
            hero: .init(emoji: "🍅", topColorHex: 0xD94D4D, bottomColorHex: 0xF58A5A, accentColorHex: 0xFFE4D6),
            ingredients: [
                .init(amount: "220", unit: "g", name: "penne"),
                .init(amount: "150", unit: "g", name: "passata"),
                .init(amount: "80", unit: "ml", name: "creme liquide"),
                .init(amount: "1", unit: "c. a soupe", name: "vodka"),
                .init(amount: "1", unit: "c. a soupe", name: "concentre de tomate"),
                .init(amount: "1", unit: "pincee", name: "flocons de chili"),
                .init(amount: "30", unit: "g", name: "parmesan")
            ],
            steps: [
                "Faites cuire les pates al dente pendant que vous preparez la sauce.",
                "Faites revenir le concentre de tomate avec les flocons de chili pendant une minute.",
                "Ajoutez la vodka, laissez reduire puis incorporez la passata et la creme.",
                "Melangez la sauce avec les pates et un peu d'eau de cuisson pour la rendre brillante.",
                "Terminez avec le parmesan et servez tres chaud."
            ]
        ),
        DemoRecipeScenario(
            id: "honey-garlic-chicken-rice",
            matchGroups: [
                ["honey", "miel", "honeygarlic"],
                ["garlic", "ail"],
                ["chicken", "poulet"],
                ["rice", "riz", "bowl"]
            ],
            title: "Poulet miel ail sur riz vapeur",
            summary: "Un plat du soir tres demo-friendly avec glaze brillant et riz bien propre.",
            servings: "2",
            prepMinutes: 15,
            cookMinutes: 18,
            hero: .init(emoji: "🍯", topColorHex: 0xC56B2E, bottomColorHex: 0xF2C05A, accentColorHex: 0xFFF0C6),
            ingredients: [
                .init(amount: "240", unit: "g", name: "filets de poulet"),
                .init(amount: "180", unit: "g", name: "riz jasmin"),
                .init(amount: "2", unit: "", name: "gousses d'ail"),
                .init(amount: "2", unit: "c. a soupe", name: "miel"),
                .init(amount: "2", unit: "c. a soupe", name: "sauce soja"),
                .init(amount: "1", unit: "c. a cafe", name: "huile de sesame"),
                .init(amount: "1", unit: "poignee", name: "cebette")
            ],
            steps: [
                "Faites cuire le riz jusqu'a ce qu'il soit bien tendre.",
                "Coupez le poulet en morceaux et faites-le dorer dans une poele chaude.",
                "Ajoutez l'ail, le miel, la sauce soja et l'huile de sesame puis laissez caraméliser legerement.",
                "Servez le poulet glace sur le riz bien chaud.",
                "Ajoutez la cebette au moment de servir."
            ]
        ),
        DemoRecipeScenario(
            id: "avocado-egg-toast",
            matchGroups: [
                ["avocado", "avocat", "avocadotoast"],
                ["toast", "pain", "sourdough"],
                ["egg", "eggs", "oeuf", "oeufs"]
            ],
            title: "Avocado toast aux oeufs mollets",
            summary: "Le classique brunch tres visuel qui rend super bien dans un import demo.",
            servings: "2",
            prepMinutes: 10,
            cookMinutes: 8,
            hero: .init(emoji: "🥑", topColorHex: 0x6DAE4F, bottomColorHex: 0xD9C85E, accentColorHex: 0xF5FFD7),
            ingredients: [
                .init(amount: "2", unit: "", name: "tranches de pain de campagne"),
                .init(amount: "1", unit: "", name: "avocat"),
                .init(amount: "2", unit: "", name: "oeufs"),
                .init(amount: "1", unit: "trait", name: "jus de citron"),
                .init(amount: "1", unit: "pincee", name: "flakes de chili"),
                .init(amount: "", unit: "", name: "sel"),
                .init(amount: "", unit: "", name: "poivre")
            ],
            steps: [
                "Faites griller le pain jusqu'a ce qu'il soit bien dore.",
                "Faites cuire les oeufs 6 a 7 minutes puis passez-les sous l'eau froide.",
                "Ecrasez l'avocat avec le citron, le sel et le poivre.",
                "Etalez l'avocat sur les toasts puis ajoutez les oeufs coupes en deux.",
                "Terminez avec quelques flakes de chili."
            ]
        ),
        DemoRecipeScenario(
            id: "crispy-potato-tacos",
            matchGroups: [
                ["taco", "tacos"],
                ["potato", "potatoes", "pomme de terre", "patate", "crispypotato"],
                ["crispy", "croustillant", "crispy potato"]
            ],
            title: "Tacos croustillants pommes de terre epicees",
            summary: "Une idee street food veggie super efficace pour une demo TikTok.",
            servings: "3",
            prepMinutes: 18,
            cookMinutes: 25,
            hero: .init(emoji: "🌮", topColorHex: 0xD36B1F, bottomColorHex: 0xF0C14D, accentColorHex: 0xFFF0CE),
            ingredients: [
                .init(amount: "350", unit: "g", name: "pommes de terre"),
                .init(amount: "6", unit: "", name: "petites tortillas"),
                .init(amount: "1", unit: "c. a soupe", name: "huile d'olive"),
                .init(amount: "1", unit: "c. a cafe", name: "paprika"),
                .init(amount: "1/2", unit: "", name: "oignon rouge"),
                .init(amount: "80", unit: "g", name: "feta emiettee"),
                .init(amount: "1", unit: "poignee", name: "coriandre")
            ],
            steps: [
                "Coupez les pommes de terre en petits cubes puis melangez-les avec l'huile et le paprika.",
                "Enfournez-les jusqu'a ce qu'elles soient bien croustillantes.",
                "Rechauffez les tortillas puis garnissez-les avec les pommes de terre, l'oignon rouge et la feta.",
                "Passez les tacos 2 minutes a la poele ou au four pour les rendre encore plus croustillants.",
                "Ajoutez la coriandre avant de servir."
            ]
        ),
        DemoRecipeScenario(
            id: "baked-feta-pasta",
            matchGroups: [
                ["feta", "baked feta", "bakedfeta"],
                ["pasta", "pates", "tomato pasta"],
                ["baked", "roasted", "au four", "oven"]
            ],
            title: "Baked feta pasta tomates rotees",
            summary: "La recette four + feta qui reste hyper reconnaissable dans un partage social.",
            servings: "3",
            prepMinutes: 10,
            cookMinutes: 30,
            hero: .init(emoji: "🧀", topColorHex: 0xD94F4F, bottomColorHex: 0xF2A65A, accentColorHex: 0xFFE7D6),
            ingredients: [
                .init(amount: "250", unit: "g", name: "pates"),
                .init(amount: "180", unit: "g", name: "bloc de feta"),
                .init(amount: "250", unit: "g", name: "tomates cerises"),
                .init(amount: "2", unit: "c. a soupe", name: "huile d'olive"),
                .init(amount: "1", unit: "", name: "gousse d'ail"),
                .init(amount: "1", unit: "poignee", name: "basilic"),
                .init(amount: "", unit: "", name: "poivre noir")
            ],
            steps: [
                "Placez les tomates et la feta dans un plat, ajoutez l'huile d'olive, l'ail et le poivre.",
                "Enfournez jusqu'a ce que les tomates eclatent et que la feta devienne cremeuse.",
                "Faites cuire les pates pendant ce temps.",
                "Ecrasez la feta et les tomates pour obtenir une sauce puis ajoutez les pates.",
                "Terminez avec le basilic frais."
            ]
        )
    ]
}
