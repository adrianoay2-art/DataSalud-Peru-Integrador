import pandas as pd
from sqlalchemy import create_engine, text
from urllib.parse import quote_plus

RUTA_VACUNACION = "data/vacunacion.csv"
RUTA_RENIPRESS = "data/renipress.csv"
ENCODING = "utf-8"          # si falla, probar "latin-1"
LIMPIAR_ANTES = True        # vacía tablas antes de cargar (permite re-ejecutar)

SERVIDOR = r"localhost\SQLEXPRESS"
BASE_DATOS = "DW_DataSalud"

CONEXION = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    f"SERVER={SERVIDOR};DATABASE={BASE_DATOS};"
    "Trusted_Connection=yes;"
)

ENGINE = create_engine(
    "mssql+pyodbc:///?odbc_connect=" + quote_plus(CONEXION),
    fast_executemany=True,
)


def limpiar_texto(serie):
    return (
        serie.astype("string")
        .str.strip()
        .str.replace(r"\s+", " ", regex=True)
    )


def leer_csv(ruta, **kwargs):
    return pd.read_csv(ruta, dtype=str, encoding=ENCODING, **kwargs)


def limpiar_tablas():
    # Orden: primero la fact, luego las dimensiones (por las FK)
    with ENGINE.begin() as con:
        for tabla in [
            "FACT_Vacunacion", "DIM_Vacuna", "DIM_Demografia",
            "DIM_Fecha", "DIM_Ubicacion", "DIM_IPRESS",
        ]:
            con.execute(text(f"DELETE FROM {tabla}"))


def cargar_dim_ipress():
    columnas = [
        "codigo_renipress", "nombre_ipress", "departamento",
        "provincia", "distrito", "tipo_establecimiento",
        "categoria_ipress", "estado_ipress",
    ]
    df = leer_csv(RUTA_RENIPRESS)[columnas].copy()

    for c in columnas:
        df[c] = limpiar_texto(df[c])

    df = df.dropna(subset=["codigo_renipress"])
    df = df.drop_duplicates(subset=["codigo_renipress"], keep="last")

    df = df.rename(columns={
        "codigo_renipress": "CodigoRenipress",
        "nombre_ipress": "NombreIPRESS",
        "departamento": "Departamento",
        "provincia": "Provincia",
        "distrito": "Distrito",
        "tipo_establecimiento": "TipoEstablecimiento",
        "categoria_ipress": "CategoriaIPRESS",
        "estado_ipress": "EstadoIPRESS",
    })

    df.to_sql("DIM_IPRESS", ENGINE, if_exists="append",
              index=False, chunksize=5000)


def cargar_dimensiones_vacunacion():
    # DIM_Vacuna
    vac = leer_csv(RUTA_VACUNACION, usecols=["tipo_vacuna"])
    vac["tipo_vacuna"] = limpiar_texto(vac["tipo_vacuna"])
    vac["tipo_vacuna"] = vac["tipo_vacuna"].fillna("NO ESPECIFICADO")
    vac = vac.rename(columns={"tipo_vacuna": "TipoVacuna"}).drop_duplicates()
    vac.to_sql("DIM_Vacuna", ENGINE, if_exists="append",
               index=False, chunksize=5000)

    # DIM_Demografia
    demo = leer_csv(RUTA_VACUNACION, usecols=["grupo_etario", "sexo"])
    demo["grupo_etario"] = limpiar_texto(demo["grupo_etario"])
    demo["sexo"] = limpiar_texto(demo["sexo"]).str.upper()
    demo["grupo_etario"] = demo["grupo_etario"].fillna("NO ESPECIFICADO")
    demo = demo[demo["sexo"].isin(["M", "F"])].drop_duplicates()
    demo = demo.rename(columns={"grupo_etario": "GrupoEtario", "sexo": "Sexo"})
    demo.to_sql("DIM_Demografia", ENGINE, if_exists="append",
                index=False, chunksize=5000)


def cargar_dim_fecha_ubicacion():
    df = leer_csv(
        RUTA_VACUNACION,
        usecols=["fecha_corte", "ubigeo", "departamento",
                 "provincia", "distrito"],
    )

    for c in ["ubigeo", "departamento", "provincia", "distrito"]:
        df[c] = limpiar_texto(df[c])

    # DIM_Fecha
    fecha = pd.to_datetime(df["fecha_corte"], errors="coerce")
    fechas = pd.DataFrame({"Fecha": fecha}).dropna().drop_duplicates()
    fechas["FechaKey"] = fechas["Fecha"].dt.strftime("%Y%m%d").astype(int)
    fechas["Año"] = fechas["Fecha"].dt.year
    fechas["Trimestre"] = fechas["Fecha"].dt.quarter
    fechas["Mes"] = fechas["Fecha"].dt.month
    fechas["NombreMes"] = fechas["Fecha"].dt.month_name()
    fechas["Dia"] = fechas["Fecha"].dt.day

    fechas[[
        "FechaKey", "Fecha", "Año", "Trimestre",
        "Mes", "NombreMes", "Dia",
    ]].to_sql("DIM_Fecha", ENGINE, if_exists="append",
              index=False, chunksize=5000)

    # DIM_Ubicacion (solo las columnas de la dimensión)
    ubic = (
        df[["ubigeo", "departamento", "provincia", "distrito"]]
        .dropna(subset=["ubigeo"])
        .drop_duplicates("ubigeo")
        .rename(columns={
            "ubigeo": "Ubigeo",
            "departamento": "Departamento",
            "provincia": "Provincia",
            "distrito": "Distrito",
        })
    )
    ubic.to_sql("DIM_Ubicacion", ENGINE, if_exists="append",
                index=False, chunksize=5000)


def _norm(serie):
    return serie.astype("string").str.strip()


def cargar_fact_vacunacion():
    ubic = pd.read_sql("SELECT UbicacionKey, Ubigeo FROM DIM_Ubicacion", ENGINE)
    ubic["Ubigeo"] = _norm(ubic["Ubigeo"])

    vacunas = pd.read_sql("SELECT VacunaKey, TipoVacuna FROM DIM_Vacuna", ENGINE)
    vacunas["TipoVacuna"] = _norm(vacunas["TipoVacuna"])

    demo = pd.read_sql(
        "SELECT DemografiaKey, GrupoEtario, Sexo FROM DIM_Demografia", ENGINE
    )
    demo["GrupoEtario"] = _norm(demo["GrupoEtario"])
    demo["Sexo"] = _norm(demo["Sexo"]).str.upper()

    grano = ["fecha_corte", "ubigeo", "tipo_vacuna", "grupo_etario", "sexo"]
    acumulado = []
    leidas = 0

    for df in pd.read_csv(RUTA_VACUNACION, dtype=str, encoding=ENCODING,
                          chunksize=100000):
        leidas += len(df)

        for c in ["departamento", "provincia", "distrito",
                  "tipo_vacuna", "grupo_etario", "sexo", "ubigeo"]:
            df[c] = limpiar_texto(df[c])

        df["fecha_corte"] = pd.to_datetime(df["fecha_corte"], errors="coerce")
        df["dosis_aplicadas"] = pd.to_numeric(
            df["dosis_aplicadas"], errors="coerce"
        )

        # Reglas de calidad
        df = df.dropna(subset=[
            "fecha_corte", "ubigeo", "departamento",
            "provincia", "distrito", "dosis_aplicadas",
        ])
        df = df[df["dosis_aplicadas"] > 0]
        df = df[df["fecha_corte"] <= pd.Timestamp.today()]
        df["sexo"] = df["sexo"].str.upper()
        df = df[df["sexo"].isin(["M", "F"])]

        df["tipo_vacuna"] = df["tipo_vacuna"].fillna("NO ESPECIFICADO")
        df["grupo_etario"] = df["grupo_etario"].fillna("NO ESPECIFICADO")

        # Agregar por grano (suma dosis en vez de descartar duplicados)
        agg = df.groupby(grano, as_index=False)["dosis_aplicadas"].sum()
        acumulado.append(agg)

    # Unificar chunks: el mismo grano puede repetirse entre bloques
    total = pd.concat(acumulado, ignore_index=True)
    total = total.groupby(grano, as_index=False)["dosis_aplicadas"].sum()
    n_antes = len(total)

    # FechaKey calculada directamente (yyyymmdd), sin lookup
    total["FechaKey"] = total["fecha_corte"].dt.strftime("%Y%m%d").astype(int)

    # Lookups de dimensiones
    total = total.merge(ubic, left_on="ubigeo", right_on="Ubigeo", how="inner")
    total = total.merge(vacunas, left_on="tipo_vacuna",
                        right_on="TipoVacuna", how="inner")
    total = total.merge(
        demo,
        left_on=["grupo_etario", "sexo"],
        right_on=["GrupoEtario", "Sexo"],
        how="inner",
    )
    print(f"Filas leídas: {leidas} | granos: {n_antes} | "
          f"cargados: {len(total)} | perdidos en lookups: "
          f"{n_antes - len(total)}")

    hechos = total[[
        "FechaKey", "UbicacionKey", "VacunaKey",
        "DemografiaKey", "dosis_aplicadas",
    ]].rename(columns={"dosis_aplicadas": "DosisAplicadas"})
    hechos["ConteoRegistros"] = 1

    hechos.to_sql("FACT_Vacunacion", ENGINE, if_exists="append",
                  index=False, chunksize=5000)


if __name__ == "__main__":
    if LIMPIAR_ANTES:
        limpiar_tablas()
    cargar_dim_ipress()
    cargar_dimensiones_vacunacion()
    cargar_dim_fecha_ubicacion()
    cargar_fact_vacunacion()
    print("ETL finalizado correctamente.")
