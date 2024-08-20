use clap::Parser;
use std::{
    io::{Read, Write},
    net::TcpStream,
    path::PathBuf,
    sync::Arc,
};

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

    /// IW4 server list URI.
    #[clap(short, long, default_value = "https://master.iw4.zip/servers")]
    uri: ParsedUri,
}

macro_rules! some_or_false {
    ($e:expr) => {
        match $e {
            Some(v) => v,
            None => return false,
        }
    };
}

fn parse_server_strings(response_body: &str, game: &Iw4Game) -> Vec<String> {
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
            let attributes = tag.attributes();

            if attributes.class()?.try_as_utf8_str() != Some("server-row") {
                return None;
            }
            let ip = tag.attributes().get("data-ip")??.try_as_utf8_str()?;
            let port = tag.attributes().get("data-port")??.try_as_utf8_str()?;
            Some(format!("    \"{}:{}\"", ip, port))
        })
        .collect::<Vec<String>>()
}

// Currently, separating this into its own function is simply unnecessary, due to its length being
// only one line. The additional function call is also inefficient. However, for future
// scalability, i.e. handling of more cases, this function is kept separate.
fn format_output(server_strings: &[String]) -> String {
    "[\n".to_string() + &server_strings.join(",\n") + "\n]\n"
}

#[derive(Clone, Default)]
struct ParsedUri {
    domain: String,
    port: String,
    path: Vec<String>,
    query: String,
}

impl ParsedUri {
    pub fn to_string(&self) -> String {
        let path = self.path.join("/");
        let query = if self.query.is_empty() {
            "".to_string()
        } else {
            "?".to_string() + self.query.as_str()
        };

        format!("{}:{}/{}{}", self.domain, self.port, path, query)
    }
}

impl std::fmt::Display for ParsedUri {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_string())
    }
}

impl From<&str> for ParsedUri {
    fn from(uri: &str) -> Self {
        let (prefix, remainder) = uri.split_once("://").unwrap_or(("http://", uri));

        if !prefix.contains("http") {
            panic!(
                "Protocol not supported! Only HTTP and HTTPS are supported. Prefix: {}",
                prefix
            );
        }

        let first_slash_index = remainder.find('/').unwrap_or(remainder.len());
        let first_colon_index = remainder.find(':').unwrap_or(remainder.len());

        let (port, remainder) = if first_colon_index < first_slash_index {
            remainder.split_once('/').unwrap_or((remainder, ""))
        } else {
            ("443", remainder)
        };

        let (remainder, query) = remainder.split_once('?').unwrap_or((remainder, ""));

        let mut domain_path = remainder
            .split('/')
            .filter(|s| !s.is_empty())
            .map(|s| s.to_string())
            .collect::<Vec<String>>();

        let path = domain_path.split_off(1);
        let domain = std::mem::take(&mut domain_path[0]);

        ParsedUri {
            domain,
            port: port.to_string(),
            path,
            query: query.to_string(),
        }
    }
}

fn request_server_list(uri: &ParsedUri) -> String {
    let root_store = rustls::RootCertStore {
        roots: webpki_roots::TLS_SERVER_ROOTS.into(),
    };

    //rustls_rustcrypto is an incomplete provider, and its security and correctness have not been formally verified nor
    //certified. However, in this case, it is functionally sufficient, and its security is of no
    //consequence, as only public server lists are intended to be accessed with this tool.
    //
    //Additionally, using rustls_rustcrypto allows compilation for additional build targets which
    //would usually break due to unusual requirements for their C compilation environments;
    //rustls_rustcrypto, as a result of being a pure rust implementation, does not share these
    //unusual compilation requirements.
    let provider = Arc::new(rustls_rustcrypto::provider());

    let mut config = rustls::ClientConfig::builder_with_provider(provider)
        .with_safe_default_protocol_versions()
        .unwrap_or_else(|e| {
            panic!(
                "Failed to set default TLS protocol versions! Error: {:?}",
                e
            )
        })
        .with_root_certificates(root_store)
        .with_no_client_auth();

    // Allow using SSLKEYLOGFILE.
    config.key_log = Arc::new(rustls::KeyLogFile::new());

    let server_name_borrowed: rustls::pki_types::ServerName =
        uri.domain.as_str().try_into().unwrap_or_else(|e| {
            panic!("Failed to parse ServerName from url! Error: {:?}", e);
        });

    let server_name = server_name_borrowed.to_owned();
    let mut conn =
        rustls::ClientConnection::new(Arc::new(config), server_name).unwrap_or_else(|e| {
            panic!("Failed to create rustls::ClientConnection! Error: {:?}", e);
        });

    let mut sock = TcpStream::connect(format!("{}:{}", uri.domain, uri.port)).unwrap_or_else(|e| {
        panic!("Failed to connect to server! Error: {:?}", e);
    });
    let mut tls = rustls::Stream::new(&mut conn, &mut sock);
    tls.write_all(
        ("GET /".to_string()
            + uri.path.join("/").as_str()
            + " "
            + "HTTP/1.0"
            + "\r\n"
            + "Host: "
            + uri.domain.as_str()
            + "\r\n"
            + "Accept: */*\r\n"
            + "\r\n")
            .as_bytes(),
    )
    .unwrap();
    let mut response_bytes = Vec::new();
    tls.read_to_end(&mut response_bytes).unwrap();

    std::str::from_utf8(response_bytes.as_slice())
        .unwrap_or_else(|_| {
            panic!("Failed to parse response from {}", uri);
        })
        .to_string()
}

fn main() {
    let args = Args::parse();

    let response_body = request_server_list(&args.uri);
    let server_strings = parse_server_strings(response_body.as_str(), &args.game);
    let out_string = format_output(server_strings.as_slice());

    std::fs::write(&args.output, out_string).unwrap_or_else(|_| {
        panic!("Failed to write to file {}", args.output.display());
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn simple_test_all() {
        let response_body = r#"
<div>
    <div id="Wrong ID">
        <></>
    </div>
    <div id="H2M_servers">
        <table>
            <tbody>
                <tr class = "server-row" data-ip="0.0.0.0" data-port="28960"></tr>
                <tr class = "server-row" data-ip="0.0.0.1" data-port="28961"></tr>
                <tr><p>Test</p></tr>
                <tr class = "server-row" data-ip="0.0.0.2" data-port="28962"></tr>
            </tbody>
        </table>
    </div>
</div>
"#;

        let game = Iw4Game::H2m;
        let server_strings = parse_server_strings(response_body, &game);
        assert_eq!(
            server_strings,
            vec![
                "    \"0.0.0.0:28960\"",
                "    \"0.0.0.1:28961\"",
                "    \"0.0.0.2:28962\""
            ]
        );

        let formatted_output = format_output(server_strings.as_slice());
        assert_eq!(
            formatted_output,
            "[\n    \"0.0.0.0:28960\",\n    \"0.0.0.1:28961\",\n    \"0.0.0.2:28962\"\n]\n"
        );
    }
}
