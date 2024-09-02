Dict(
    :main => [
        "welcome" => collections["welcome"].pages,
        "Preliminaries" => collections["preliminaries"].pages,
        "Module 1: Introduction to agent based modelling" => collections["module1"].pages,
        #"Module 3: Climate Science" => collections["module3"].pages,

    ],
    :about => Dict(
        :authors => [
            (name = "Steven Hoekstra", url = "https://www.the-one.eu"),
            (name = "Cars Hommes", url = "https://www.the-second.com")
        ],
        :title => "Behavioral Macro and Finance",
        :subtitle => "Agent Based Modelling",
        :term => "Spring 2023",
        :institution => "University of Amsterdam",
        :institution_url => "http://www.uva.nl",
        :institution_logo => "julia-logo-color.svg",
        :institution_logo_darkmode => "julia-logo-dark.svg"
    )
)