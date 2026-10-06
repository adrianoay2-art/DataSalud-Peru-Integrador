
pip install pandas sqlalchemy pyodbc

import pandas as pd from sqlalchemy import create_engine from urllib.parse import quote_plus 
 
RUTA_VACUNACION = "data/vacunacion.csv" 
RUTA_RENIPRESS = "data/renipress.csv" 
 
SERVIDOR = r"localhost\SQLEXPRESS" 
BASE_DATOS = "DW_DataSalud" 
 
CONEXION = ( 
    "DRIVER={ODBC Driver 17 for SQL Server};"     f"SERVER={SERVIDOR};DATABASE={BASE_DATOS};" 
    "Trusted_Connection=yes;" 
) 
 
ENGINE = create_engine( 
    "mssql+pyodbc:///?odbc_connect=" + quote_plus(CONEXION),     fast_executemany=True 
)  def limpiar_texto(serie):     return (serie.astype("string") 
            .str.strip() 
            .str.replace(r"\s+", " ", regex=True)) 
 def cargar_dim_ipress(): 
    df = pd.read_csv(RUTA_RENIPRESS, dtype=str) 
     columnas = [ 
        "codigo_renipress", "nombre_ipress", "departamento", 
        "provincia", "distrito", "tipo_establecimiento", 
        "categoria_ipress", "estado_ipress" 
    ]     df = df[columnas].copy() 
     for c in columnas: 
        df[c] = limpiar_texto(df[c]) 
     df = df.dropna(subset=["codigo_renipress"]) 
 

    df = df.drop_duplicates(         subset=["codigo_renipress"], keep="last" 
    )      df = df.rename(columns={ 
        "codigo_renipress": "CodigoRenipress", 
        "nombre_ipress": "NombreIPRESS", 
        "departamento": "Departamento", 
        "provincia": "Provincia", 
        "distrito": "Distrito", 
        "tipo_establecimiento": "TipoEstablecimiento", 
        "categoria_ipress": "CategoriaIPRESS", 
        "estado_ipress": "EstadoIPRESS" 
    })      df.to_sql( 
        "DIM_IPRESS", ENGINE,         if_exists="append", index=False, chunksize=5000     )  def cargar_dimensiones_vacunacion():     # DIM_Vacuna     vac = pd.read_csv(         RUTA_VACUNACION,         usecols=["tipo_vacuna"], dtype=str 
    )     vac["tipo_vacuna"] = limpiar_texto(vac["tipo_vacuna"])     vac["tipo_vacuna"] = vac["tipo_vacuna"].fillna("NO ESPECIFICADO")     vac = vac.rename(columns={"tipo_vacuna": "TipoVacuna"})     vac = vac.drop_duplicates()     vac.to_sql( 
        "DIM_Vacuna", ENGINE,         if_exists="append", index=False, chunksize=5000     ) 
 
    # DIM_Demografia     demo = pd.read_csv(         RUTA_VACUNACION,         usecols=["grupo_etario", "sexo"], dtype=str 
    )     demo["grupo_etario"] = limpiar_texto(demo["grupo_etario"])     demo["sexo"] = limpiar_texto(demo["sexo"]).str.upper()     demo["grupo_etario"] = demo["grupo_etario"].fillna("NO ESPECIFICADO")     demo = demo[demo["sexo"].isin(["M", "F"])]     demo = demo.drop_duplicates() 
     demo = demo.rename(columns={ 
        "grupo_etario": "GrupoEtario", 
        "sexo": "Sexo" 
    }) 
    demo.to_sql( 
        "DIM_Demografia", ENGINE,         if_exists="append", index=False, chunksize=5000     )  def cargar_dim_fecha_ubicacion(): 

    df = pd.read_csv(         RUTA_VACUNACION,         usecols=[ 
            "fecha_corte", "ubigeo", "departamento", 
            "provincia", "distrito" 
        ],         dtype=str 
    )      for c in ["ubigeo", "departamento", "provincia", "distrito"]: 
        df[c] = limpiar_texto(df[c]) 
 
    # DIM_Fecha     fecha = pd.to_datetime(         df["fecha_corte"], errors="coerce" 
    )     fechas = pd.DataFrame({"Fecha": fecha}).dropna().drop_duplicates()     fechas["FechaKey"] = fechas["Fecha"].dt.strftime("%Y%m%d").astype(int)     fechas["Año"] = fechas["Fecha"].dt.year     fechas["Trimestre"] = fechas["Fecha"].dt.quarter     fechas["Mes"] = fechas["Fecha"].dt.month     fechas["NombreMes"] = fechas["Fecha"].dt.month_name()     fechas["Dia"] = fechas["Fecha"].dt.day 
     fechas[[ 
        "FechaKey", "Fecha", "Año", "Trimestre", 
        "Mes", "NombreMes", "Dia" 
    ]].to_sql( 
        "DIM_Fecha", ENGINE,         if_exists="append", index=False, chunksize=5000     ) 
 
    # DIM_Ubicacion     ubic = df.dropna(subset=["ubigeo"]).drop_duplicates("ubigeo")     ubic = ubic.rename(columns={ 
        "ubigeo": "Ubigeo", 
        "departamento": "Departamento", 
        "provincia": "Provincia", 
        "distrito": "Distrito" 
    }) 
    ubic.to_sql( 
        "DIM_Ubicacion", ENGINE,         if_exists="append", index=False, chunksize=5000     )  def cargar_fact_vacunacion(): 
    fechas = pd.read_sql( 
        "SELECT FechaKey, Fecha FROM DIM_Fecha", ENGINE 
    )     ubic = pd.read_sql( 
        "SELECT UbicacionKey, Ubigeo FROM DIM_Ubicacion", ENGINE 
    )     vacunas = pd.read_sql( 
        "SELECT VacunaKey, TipoVacuna FROM DIM_Vacuna", ENGINE 
    )     demo = pd.read_sql( 

        "SELECT DemografiaKey, GrupoEtario, Sexo FROM DIM_Demografia", 
        ENGINE 
    )  
    for df in pd.read_csv(         RUTA_VACUNACION,         dtype=str,         chunksize=100000     ):         for c in [ 
            "departamento", "provincia", "distrito", 
            "tipo_vacuna", "grupo_etario", "sexo", "ubigeo"         ]:             df[c] = limpiar_texto(df[c]) 
         df["fecha_corte"] = pd.to_datetime(             df["fecha_corte"], errors="coerce" 
        )         df["dosis_aplicadas"] = pd.to_numeric(             df["dosis_aplicadas"], errors="coerce" 
        ) 
 
        # Reglas de calidad         df = df.dropna(subset=[ 
            "fecha_corte", "ubigeo", "departamento", 
            "provincia", "distrito", "dosis_aplicadas" 
        ])         df = df[df["dosis_aplicadas"] > 0]         df = df[df["fecha_corte"] <= pd.Timestamp.today()]         df["sexo"] = df["sexo"].str.upper()         df = df[df["sexo"].isin(["M", "F"])] 
 
        # Grano definido para la tabla de hechos         df = df.drop_duplicates(subset=[ 
            "fecha_corte", "ubigeo", "tipo_vacuna", 
            "grupo_etario", "sexo" 
        ]) 
 
        # Lookup de dimensiones         df = df.merge(             fechas, left_on="fecha_corte",             right_on="Fecha", how="inner" 
        )         df = df.merge(             ubic, left_on="ubigeo",             right_on="Ubigeo", how="inner" 
        ) 
         df["tipo_vacuna"] = df["tipo_vacuna"].fillna("NO ESPECIFICADO")         df = df.merge(             vacunas, left_on="tipo_vacuna",             right_on="TipoVacuna", how="inner" 
        ) 
         df["grupo_etario"] = df["grupo_etario"].fillna("NO ESPECIFICADO")         df = df.merge( 
            demo,             left_on=["grupo_etario", "sexo"],             right_on=["GrupoEtario", "Sexo"],             how="inner" 
        ) 
         hechos = df[[ 
            "FechaKey", "UbicacionKey", "VacunaKey", 
            "DemografiaKey", "dosis_aplicadas" 
        ]].copy() 
         hechos = hechos.rename(columns={ 
            "dosis_aplicadas": "DosisAplicadas" 
        })         hechos["ConteoRegistros"] = 1 
         hechos.to_sql( 
            "FACT_Vacunacion", ENGINE,             if_exists="append", index=False, chunksize=5000 
        ) 
 if __name__ == "__main__":     cargar_dim_ipress()     cargar_dimensiones_vacunacion()     cargar_dim_fecha_ubicacion()     cargar_fact_vacunacion()     print("ETL finalizado correctamente.") 
