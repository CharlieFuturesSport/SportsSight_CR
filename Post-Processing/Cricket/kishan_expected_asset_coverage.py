import argparse
from pathlib import Path

import pandas as pd


EXPECTED_PAIRS = [
    ("Barclays", "Elevated Signage"),
    ("Barclays", "Media Backdrop"),
    ("Barclays", "Media Backdrop"),
    ("Barclays", "Sightscreen"),
    ("Barclays", "Perimeter Board"),
    ("Castore", "Bib"),
    ("Castore", "Cap"),
    ("Castore", "Elevated Signage"),
    ("Castore", "Jersey - Shirt Front - Upper Chest"),
    ("Castore", "Jersey - Shirt Front - Upper Chest"),
    ("Castore", "Perimeter Board"),
    ("Cawston Press", "Perimeter Board"),
    ("CGI", "Elevated Signage"),
    ("CGI", "Perimeter Board"),
    ("IG", "Elevated Signage"),
    ("IG", "Jersey - Shirt Front - Sleeve"),
    ("IG", "Perimeter Board"),
    ("London Pride", "Elevated Signage"),
    ("Peroni", "Elevated Signage"),
    ("Peroni", "Perimeter Board"),
    ("Remitly", "Perimeter Board"),
    ("Rothesay", "Boundary Rope"),
    ("Rothesay", "Pitch Mat"),
    ("Rothesay", "Stumps"),
    ("Rothesay", "Perimeter Board"),
    ("Rothesay", "Sightscreen"),
    ("Toyota", "Bib"),
    ("Toyota", "Bib"),
    ("Toyota", "Cap"),
    ("Toyota", "Elevated Signage"),
    ("Toyota", "Jersey - Shirt Back - Upper"),
    ("Toyota", "Jersey - Shirt Front - Centre"),
    ("Toyota", "Jersey - Shirt Front - Sleeve"),
    ("Toyota", "Perimeter Board"),
    ("Tyrrells", "Perimeter Board"),
    ("Tyrrells", "Jersey - Shirt Front - Sleeve"),
    ("Vitality", "Jersey - Shirt Back - Upper"),
    ("Vitality", "Perimeter Board"),
    ("Vitality", "Elevated Signage"),
    ("Whole Earth", "Perimeter Board"),
    ("Whole Earth", "Cap"),
    ("Whole Earth", "Jersey - Shirt Front - Centre"),
    ("Whole Earth", "Jersey - Shirt Front - Upper Chest"),
]


def build_report(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for idx, (brand, asset) in enumerate(EXPECTED_PAIRS, start=1):
        mask = (
            (df["Brand"].str.lower() == brand.lower())
            & (df["Asset"].str.lower() == asset.lower())
        )
        subset = df.loc[mask]
        count_rows = int(len(subset))
        exposure_sum = float(subset["AcceptedExposure"].sum())
        rows.append(
            {
                "Idx": idx,
                "Brand": brand,
                "Asset": asset,
                "Rows": count_rows,
                "Exposure": round(exposure_sum, 2),
                "Status": "FOUND" if count_rows > 0 else "MISSING",
            }
        )
    return pd.DataFrame(rows)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Compare expected Kishan brand-assets against final output CSV."
    )
    parser.add_argument(
        "--input",
        default="Post-Processing/Cricket/outputs/pls_ECB_WIT20_v2.csv",
        help="Path to final output CSV.",
    )
    parser.add_argument(
        "--output",
        default="Post-Processing/Cricket/outputs/kishan_expected_asset_coverage_report.csv",
        help="Path to write report CSV.",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    df = pd.read_csv(input_path)
    df["Brand"] = df["Brand"].fillna("").astype(str).str.strip()
    df["Asset"] = df["Asset"].fillna("").astype(str).str.strip()
    df["AcceptedExposure"] = pd.to_numeric(
        df.get("AcceptedExposure", 0), errors="coerce"
    ).fillna(0)

    report = build_report(df)
    report.to_csv(output_path, index=False)

    found = int((report["Rows"] > 0).sum())
    total = len(report)
    unique = report[["Brand", "Asset"]].drop_duplicates().copy()
    unique = unique.merge(
        report.groupby(["Brand", "Asset"], as_index=False)["Rows"].sum(),
        on=["Brand", "Asset"],
        how="left",
    )
    unique_found = int((unique["Rows"] > 0).sum())

    print(report.to_string(index=False))
    print("\nSUMMARY")
    print(f"Entries (including duplicates): {total}")
    print(f"Found (including duplicates): {found}")
    print(f"Missing (including duplicates): {total - found}")
    print(f"Unique expected pairs: {len(unique)}")
    print(f"Unique found pairs: {unique_found}")
    print(f"Unique missing pairs: {len(unique) - unique_found}")
    print(
        "Total exposure across expected list: "
        f"{round(float(report['Exposure'].sum()), 2)}"
    )

    print("\nUNIQUE MISSING PAIRS")
    for _, row in unique[unique["Rows"] == 0].sort_values(["Brand", "Asset"]).iterrows():
        print(f"- {row['Brand']} | {row['Asset']}")

    print(f"\nSaved report to: {output_path}")


if __name__ == "__main__":
    main()
