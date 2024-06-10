use crate::backend::coord::Coord;
use anyhow::{anyhow, Result};
use itertools::Itertools;
use serde_json::Value;
use tera::Tera;
pub enum Dir {
    Forward,
    Backward,
}

const FORWARD_REQUEST_TEMPLATE: &str = r#"{
    "destination":{
        "type":"Module",
        "target":"/osrm/one_to_many"
    },
    "content_type":"OSRMOneToManyRequest",
    "content":{
        "profile":"car",
        "direction":"Forward",
        "one":{
            "lat":{{ one.y }},
            "lng":{{ one.x }}
        },
        "many": {{ many }}
    }
}"#;

#[allow(dead_code)]
const BACKWARD_REQUEST_TEMPLATE: &str = r#"{
    "destination":{
        "type":"Module",
        "target":"/osrm/one_to_many"
    },
    "content_type":"OSRMOneToManyRequest",
    "content":{
        "profile":"car",
        "direction":"Backward",
        "one":{
            "lat":{{ one.y }},
            "lng":{{ one.x }}
        },
        "many": {{ many }}
    }
}"#;

#[derive(Debug, Copy, Clone)]
pub struct DistTime {
    pub dist: f64,
    pub time: f64,
}

#[derive(Clone)]
pub struct OSRM {
    client: reqwest::Client,
    tera: tera::Tera,
}

impl OSRM {
    pub fn new() -> Self {
        let mut tera = Tera::default();
        tera.add_raw_template("x", FORWARD_REQUEST_TEMPLATE)
            .unwrap();
        let client = reqwest::Client::new();
        Self { tera, client }
    }

    pub async fn one_to_many(
        &self,
        one: &Coord,
        many: &[Coord],
        direction: Dir,
    ) -> Result<Vec<DistTime>> {
        let mut ctx = tera::Context::new();
        let one = one.get_coord();
        let many = many.iter().map(|c| c.get_coord()).collect_vec();
        ctx.try_insert("one", &one)?;
        ctx.try_insert(
            "many",
            &serde_json::to_string(&many)
                .unwrap()
                .replace('y', "lat")
                .replace('x', "lng"),
        )?;

        let request = self.tera.render("x", &ctx)?;
        let mut res = self
            .client
            .post("https://europe.motis-project.de/")
            .body(request)
            .send()
            .await?
            .text()
            .await?;
        res = res.replace("179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368",
             &format!("{}", 99999999).to_string());

        let v_res: Result<Value, serde_json::Error> = serde_json::from_str(&res);
        let v = match v_res {
            Ok(v) => v,
            Err(e) => {
                println!("serde error when deserializing osrm-response: {}", e);
                return Err(e.into());
            }
        };

        Ok(v.get("content")
            .ok_or_else(|| anyhow!("MOTIS response had no content"))?
            .get("costs")
            .ok_or_else(|| anyhow!("MOTIS response had no costs"))?
            .as_array()
            .ok_or_else(|| anyhow!("MOTIS costs were not an array"))?
            .iter()
            .filter_map(|e| {
                Some(DistTime {
                    dist: e.get("distance")?.as_f64()?,
                    time: e.get("duration")?.as_f64()?,
                })
            })
            .collect())
    }
}

#[cfg(test)]
mod test {
    use crate::{
        backend::lat_long::{Latitude, Longitude},
        constants::geojson_strings::geo_points::TestPoints,
        osrm::{
            Coord,
            Dir::{Backward, Forward},
            OSRM,
        },
    };
    use anyhow::Result;

    #[tokio::test]
    async fn osrm_test1() -> Result<()> {
        let osrm = OSRM::new();
        let result = osrm
            .one_to_many(
                &Coord::new(Latitude::new(49.87738), Longitude::new(8.645554)),
                &[
                    Coord::new(Latitude::new(50.114854), Longitude::new(8.657913)),
                    Coord::new(Latitude::new(49.39444), Longitude::new(8.674393)),
                ],
                Forward,
            )
            .await?;
        println!("result: {result:?}");
        Ok(())
    }

    #[tokio::test]
    async fn osrm_test2() -> Result<()> {
        let osrm = OSRM::new();
        let test_points = TestPoints::new();
        let result = osrm
            .one_to_many(
                &Coord::from(test_points.bautzen_west[0]),
                &[
                    Coord::from(test_points.bautzen_west[1]),
                    Coord::from(test_points.bautzen_west[2]),
                ],
                Forward,
            )
            .await?;
        println!("result: {result:?}");
        Ok(())
    }
}
