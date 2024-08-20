use clap::Parser;
use std::path::PathBuf;

//Note - enum argument parsing is case-insensitive. https://master.iw4.zip/servers uses all
//uppercase letters for each of these enum options, so these will still work, while keeping with
//Rust naming conventions.
#[derive(Debug, Clone, Default, Copy)]
enum Iw4Game {
    Cod,
    H1,
    #[default]
    H2m,
    Iw3,
    Iw4,
    Iw5,
    Iw6,
    L4d2,
    Shg1,
    T4,
    T5,
    T6,
    T7,
}

// TODO: this can be a derive proc macro + a const function for formatted string {}_servers
impl Iw4Game {
    pub fn as_html_id(&self) -> &str {
        match self {
            Iw4Game::Cod => "COD_servers",
            Iw4Game::H1 => "H1_servers",
            Iw4Game::H2m => "H2M_servers",
            Iw4Game::Iw3 => "IW3_servers",
            Iw4Game::Iw4 => "IW4_servers",
            Iw4Game::Iw5 => "IW5_servers",
            Iw4Game::Iw6 => "IW6_servers",
            Iw4Game::L4d2 => "L4D2_servers",
            Iw4Game::Shg1 => "SHG1_servers",
            Iw4Game::T4 => "T4_servers",
            Iw4Game::T5 => "T5_servers",
            Iw4Game::T6 => "T6_servers",
            Iw4Game::T7 => "T7_servers",
        }
    }
}

impl From<&str> for Iw4Game {
    fn from(s: &str) -> Self {
        match s.to_lowercase().as_str() {
            "cod" => Iw4Game::Cod,
            "h1" => Iw4Game::H1,
            "h2m" => Iw4Game::H2m,
            "iw3" => Iw4Game::Iw3,
            "iw4" => Iw4Game::Iw4,
            "iw5" => Iw4Game::Iw5,
            "iw6" => Iw4Game::Iw6,
            "l4d2" => Iw4Game::L4d2,
            "shg1" => Iw4Game::Shg1,
            "t4" => Iw4Game::T4,
            "t5" => Iw4Game::T5,
            "t6" => Iw4Game::T6,
            "t7" => Iw4Game::T7,
            _ => Iw4Game::H2m,
        }
    }
}

#[derive(Parser)]
#[command(version, about, long_about = None)]
struct Args {
    /// Output file for server list.
    #[clap(short, long, default_value = "favourites.json")]
    output: PathBuf,
    /// Game to get server list for.
    /// Options: COD, H1, H2M, IW3, IW4, IW5, IW6, L4D2, SHG1, T4, T5, T6, T7.
    #[clap(short, long, default_value = "H2M")]
    game: Iw4Game,

    /// IW4 server list URL.
    #[clap(short, long, default_value = "https://master.iw4.zip/servers")]
    url: String,
}

macro_rules! some_or_false {
    ($e:expr) => {
        match $e {
            Some(v) => v,
            None => return false,
        }
    };
}

fn parse_sever_strings(response_body: &str, game: &Iw4Game) -> Vec<String> {
    let game_html_id = game.as_html_id();

    let dom = tl::parse(response_body, tl::ParserOptions::default()).unwrap();
    let parser = dom.parser();

    let game_server_panel_div_handle = dom.get_element_by_id(game_html_id).unwrap_or_else(|| {
        panic!("Failed to parse response for id: {}", game_html_id);
    });

    let game_server_panel_div = game_server_panel_div_handle
        .get(parser)
        .unwrap()
        .as_tag()
        .unwrap();

    let table_handle = game_server_panel_div
        .find_node(parser, &mut |node| {
            some_or_false!(node.as_tag()).name().try_as_utf8_str() == Some("table")
        })
        .unwrap_or_else(|| {
            panic!("Failed to find table in game server panel div");
        });
    let table = table_handle.get(parser).unwrap();
    let table_body_handle = table
        .find_node(parser, &mut |node| {
            some_or_false!(node.as_tag()).name().try_as_utf8_str() == Some("tbody")
        })
        .unwrap_or_else(|| {
            panic!("Failed to find tbody in game server panel div");
        });
    let table_body = table_body_handle.get(parser).unwrap().as_tag().unwrap();

    table_body
        .children()
        .top()
        .iter()
        .filter_map(|child_handle| {
            let child = child_handle.get(parser)?;
            let tag = child.as_tag()?;
            let ip = tag.attributes().get("data-ip")??.try_as_utf8_str()?;
            let port = tag.attributes().get("data-port")??.try_as_utf8_str()?;
            Some(format!("{}:{}", ip, port))
        })
        .collect::<Vec<String>>()
}

// Currently, separating this into its own function is simply unnecessary, due to its length being
// only one line. The additional function call is also inefficient. However, for future
// scalability, i.e. handling of more cases, this function is kept separate.
fn format_output(server_strings: Vec<String>) -> String {
    "[\n".to_string() + &server_strings.join(",\n") + "\n]\n"
}

fn main() {
    let args = Args::parse();

    let response_body: String = ureq::get(args.url.as_str())
        .call()
        .unwrap_or_else(|_| {
            panic!("Failed to get server list from {}", args.url.as_str());
        })
        .into_string()
        .unwrap_or_else(|_| {
            panic!("Failed to parse response from {}", args.url.as_str());
        });

    let server_strings = parse_sever_strings(&response_body, &args.game);
    let out_string = format_output(server_strings);

    std::fs::write(&args.output, out_string).unwrap_or_else(|_| {
        panic!("Failed to write to file {}", args.output.display());
    });
}
