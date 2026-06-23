# -*- coding: utf-8 -*-
"""
@author: Ernest.Teh
SportsSight_Final_Process_WSL
"""
import pandas as pd
import numpy as np
import sys
import time
import math
from datetime import datetime

sys.path.insert(0, r'Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\Python Helper Scripts')
import sql_helper_LR as lr

sys.path.insert(0, r'Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\OCR Coords')
import SportsSight_OCR_coordinates as coord

sys.path.insert(0, r'Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\Post-Processing\Cricket')
import SportsSight_functions_ECB as func

# ============================================================================
# CONFIGURATION
# ============================================================================

inputFile    = r"Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\Post-Processing\Cricket\SportSight - Brand Asset Methodology - ECB (new v2).xlsx"
output_folder = r"Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\Post-Processing\Cricket"

sport       = 'cricket'
sqlServer   = 'inf'
sqlDatabase = 'ECB'
iteration   = 'SS1'

# OCR coordinate tolerances (position/size relative to image; angle in degrees)
ocr_position_tolerance = 0.05
ocr_size_tolerance     = 0.2
ocr_angle_tolerance    = 5.0

listOfEvents = [
'12706_020626_Women_3rdT20I_Eng_v_Ind',
'12705_300526_Women_2ndT20I_Eng_v_Ind',
'12704_280526_Women_1stT20I_Eng_v_Ind'
]

missingOCRStep = True

# Brand normalisation for missing OCR step — set to None if not needed
brand_norm = None
# {    'Barclays': 'Barclays_All',
#     'Barclays WSL': 'Barclays_All',
#     'Barclays Solus': 'Barclays_All' } # None

# Assets to include in missing OCR matching — set to None to include all
valid_assets_list = [
'Cap',
'Elevated Signage',
'Helmet',
'Jersey - Shirt Back - Upper',
'Jersey - Shirt Front - Sleeve',
'Boundary Rope',
'Jersey - Shirt Front - Centre',
'Jersey - Shirt Front - Upper Chest',
'Media Backdrop',
'Perimeter Board',
'Sightscreen',
'Trousers',
'Bib',
'Dugout Backing',
'Giant Screen',
'Jersey',
'Microphone',
'Pitch Mat',
'Stumps',
'Spectator Cards',
'Indoor Screens',
'Medal',
'Trophy Plinth',
'Winner Board',
'Trophy',
'TVGI - Scorecard',
'Pyro Box',
'Wine Bottle',
'Wine Bottle Plinth'
]

# Brand corrections applied during missing OCR matching
corrections = None
# [   {'asset': 'Club Sleeve Branding', 'normalised_brand': 'Barclays_All', 'corrected_brand': 'Barclays WSL'},
#     {'asset': 'Broadcast overlays', 'normalised_brand': 'Barclays_All', 'corrected_brand': 'Barclays WSL'},
#     {'asset': 'Goal-Side Wedge', 'normalised_brand': 'Barclays_All', 'corrected_brand': 'Barclays Solus'} ]

# Pass 1: Brand -> Asset for Unassigned rows
unassigned_brand_asset_map = None
# {
#     'Mercedes-Benz': 'Perimeter Board',
#     'Mercedes':  'Perimeter Board'
# }

# Pass 2: (IC prediction, Brand) -> Asset for still-Unassigned rows
unassigned_ic_asset_map = None
# {
#     ('Interview Backdrop',    'Barclays Solus'): 'Interview Backdrop',
#     ('Interview Backdrop', 'Barclays WSL'):     'Interview Backdrop',
#     ('Interview Backdrop',  'British Gas'):     'Interview Backdrop',
#     ('Interview Backdrop',        'Sky'):     'Interview Backdrop',
#     ('Player-Ref Close Up',       'Sky'):     'Corner Board',
#     ('Player Walk Out',       'Sky'):     'Corner Board',
#     ('Player-Ref Close Up',  'British Gas'):     'Perimenter Board',
#     ('Dugout',  'British Gas'):     'Perimeter Board',
#     ('Field Shot - Left - Zoom',  'British Gas'):     'Perimeter Board',
#     ('Field Shot - Right - Zoom',  'British Gas'):     'Perimeter Board',
#     ('Field Shot - Centre - Zoom',  'British Gas'):     'Perimeter Board',
#     ('Player Walk Out',  'British Gas'):     'Perimeter Board',
#     ('Field Shot - Centre - Zoom',  'Barclays WSL'):     'Perimeter Board',
#     ('Field Shot - Centre - Zoom',  'Barclays Solus'):     'Perimeter Board'
# }

# ============================================================================
# SETUP
# ============================================================================

overall_start_time = time.perf_counter()
brandAsset_method  = pd.read_excel(inputFile, 'BrandAssetMethodology')
dateStamp          = datetime.today().strftime('%Y%m%d')

if input("Upload brand asset methodology to SQL for reference? (Y/N): ").upper() == 'Y':
    lr.toSQL(brandAsset_method, sqlServer, sqlDatabase, f'SportsSight_BrandAssetMethod_{dateStamp}')

# ============================================================================
# OCR COORDINATES PREP
# ============================================================================

ocr_coords = brandAsset_method[
    (brandAsset_method['BrandAssetPairing'].isna()) &
    (brandAsset_method['OCR'].isna()) &
    (brandAsset_method['OCR_coordinates'] == 1) &
    (brandAsset_method['IC'].isna()) &
    (brandAsset_method['BrandOnly'].isna()) &
    (brandAsset_method['AssetOnly'].isna()) &
    (brandAsset_method['Creative'].isna())
].copy()

if not ocr_coords.empty:
    if input("Have you already processed the TVGIs based on coordinates? (Y/N): ").upper() == 'N':
        output_path    = fr"{output_folder}\TVGI_detection_report_{sport}_{dateStamp}.xlsx"
        events_number  = len(listOfEvents)
        sample_all     = events_number <= 5

        print(f"Starting OCR coordinate process on {'all' if sample_all else 'sample of 5'} events.")

        if sample_all:
            events_to_sample = listOfEvents
        else:
            n = math.floor(events_number / 5.0)
            events_to_sample = [listOfEvents[n * y] for y in range(5)]

        events_str = ",".join(f"'{e}/'" for e in events_to_sample)
        ocrResults_sample = lr.fromSQLquery(f"""
            SELECT * FROM Toolkit_Cleaned_OCR_Results
            WHERE SportsEvent IN ({events_str})
            ORDER BY SportsEvent, Filename, ID
        """, sqlServer, sqlDatabase)
        print("Cleaned OCR results collected.")

        ocr_tvgi_coords = coord.ocr_coords_toSQL_proc(
            ocrResults_sample,
            [e + '/' for e in events_to_sample],
            output_path=output_path,
            iteration=iteration,
            group_events=True,
            brands=['Vitality'],
            cleaned_text_list=['Vitality'],
            position_tolerance=ocr_position_tolerance,
            size_tolerance=ocr_size_tolerance,
            angle_tolerance=ocr_angle_tolerance,
            min_frames=10,
        )

        sql_tvgi_table = input('Name for the new OCR TVGI coordinate table in SQL: ')
        lr.toSQL(ocr_tvgi_coords, sqlServer, sqlDatabase, sql_tvgi_table)
        print("OCR TVGI coordinates uploaded to SQL.")

    else:
        sql_tvgi_table = input('Name of the existing OCR TVGI coordinate table in SQL: ')
        ocr_tvgi_coords = lr.fromSQLquery(
            f"SELECT * FROM {sql_tvgi_table}", sqlServer, sqlDatabase
        )
        print("OCR coordinates loaded.")

# ============================================================================
# PER-EVENT PROCESSING
# ============================================================================

def exposurePerEvent(match):
    start_time = time.perf_counter()

    # Initialise all result variables as empty so they always exist
    ocrResults        = pd.DataFrame()
    brandAssetResults = pd.DataFrame()
    assetResults      = pd.DataFrame()
    brandResults      = pd.DataFrame()
    icResults         = pd.DataFrame()

    # ── SQL queries ──────────────────────────────────────────────────────────
    if brandAsset_method['OCR'].notna().any() or brandAsset_method['OCR_coordinates'].notna().any():
        try:
            ocrResults = lr.fromSQLquery(f"""
                SELECT * FROM Toolkit_Cleaned_OCR_Results
                WHERE SportsEvent LIKE '{match}/'
            """, sqlServer, sqlDatabase)
            imageSize_df = lr.fromSQLquery(f"""
                SELECT imageHeight, imageWidth FROM Toolkit_Cleaned_OCR_Results
                WHERE SportsEvent LIKE '{match}/'
                GROUP BY imageHeight, imageWidth
            """, sqlServer, sqlDatabase)
            imageWidth  = int(imageSize_df.iloc[0, 1])
            imageHeight = int(imageSize_df.iloc[0, 0])
            imageSize   = imageWidth * imageHeight

            #Define coordinates in order to work out a rough rectangular area          
            x_cols = [
                'BoxTopLeftX',
                'BoxTopRightX',
                'BoxBottomRightX',
                'BoxBottomLeftX'
            ]

            y_cols = [
                'BoxTopLeftY',
                'BoxTopRightY',
                'BoxBottomRightY',
                'BoxBottomLeftY'
            ]
            
            #Calculate area using those coordinates           
            ocr_width = (
                ocrResults[x_cols].max(axis=1)
                - ocrResults[x_cols].min(axis=1)
            )

            ocr_height = (
                ocrResults[y_cols].max(axis=1)
                - ocrResults[y_cols].min(axis=1)
            )

            ocrResults['Box_Size_Perc'] = (
                ocr_width * ocr_height
            ) / imageSize

        except Exception:
            print("No results in Toolkit_Cleaned_OCR_Results table")
            sys.exit(1)

    if brandAsset_method['BrandAssetPairing'].notna().any():
        try:
            brandAssetResults = lr.fromSQLquery(f"""
                SELECT * FROM SportsSight_Raw_BrandAssets WHERE SportsEvent = '{match}'
            """, sqlServer, sqlDatabase)
            ba_width  = (brandAssetResults['BrandBottomRightX'] - brandAssetResults['BrandTopLeftX']).abs()
            ba_height = (brandAssetResults['BrandBottomRightY'] - brandAssetResults['BrandTopLeftY']).abs()
            brandAssetResults['Box_Size_Perc'] = (ba_width * ba_height) / imageSize
        except Exception:
            print("No SportsSight_Raw_BrandAssets table found")
            sys.exit(1)

    try:
        assetResults = lr.fromSQLquery(f"""
            SELECT * FROM SportsSight_Raw_Assets WHERE SportsEvent = '{match}'
        """, sqlServer, sqlDatabase)
        a_width  = (assetResults['BottomRightX'] - assetResults['TopLeftX']).abs()
        a_height = (assetResults['BottomRightY'] - assetResults['TopLeftY']).abs()
        assetResults['Box_Size_Perc'] = (a_width * a_height) / imageSize
    except Exception:
        print("No SportsSight_Raw_Assets table found")

    if brandAsset_method['BrandOnly'].notna().any():
        try:
            brandResults = lr.fromSQLquery(f"""
                SELECT * FROM SportsSight_Raw_Brands WHERE SportsEvent = '{match}'
            """, sqlServer, sqlDatabase)
            b_width  = (brandResults['BottomRightX'] - brandResults['TopLeftX']).abs()
            b_height = (brandResults['BottomRightY'] - brandResults['TopLeftY']).abs()
            brandResults['Box_Size_Perc'] = (b_width * b_height) / imageSize
        except Exception:
            print("No SportsSight_Raw_Brands table found")
            sys.exit(1)

    # if brandAsset_method['IC'].notna().any():
    try:
        icResults = lr.fromSQLquery(f"""
                SELECT * FROM SportsSight_Raw_Classifications WHERE SportsEvent = '{match}'
            """, sqlServer, sqlDatabase)
    except Exception:
        print("No SportsSight_Raw_Classifications table found")
        sys.exit(1)

    # ── Helper: filter methodology rows ──────────────────────────────────────
    def method_filter(**flags):
        """
        Returns rows from brandAsset_method matching the given column conditions.
        Pass column=value for equality, column=None to require NaN.
        e.g. method_filter(BrandAssetPairing=1, OCR=None, IC=None)
        """
        mask = pd.Series(True, index=brandAsset_method.index)
        for col, val in flags.items():
            if val is None:
                mask &= brandAsset_method[col].isna()
            else:
                mask &= (brandAsset_method[col] == val)
        return brandAsset_method[mask].copy()

    # ── Step 0: OCR coordinates ───────────────────────────────────────────────
    if not ocr_coords.empty:
        finalResults0 = coord.apply_SQL_coords(
            ocrResults, ocr_tvgi_coords, iteration,
            position_tolerance=ocr_position_tolerance,
            size_tolerance=ocr_size_tolerance,
            angle_tolerance=ocr_angle_tolerance,
        )
        print('OCR coordinate results completed.')
    else:
        finalResults0 = pd.DataFrame()

    # ── Steps 1–11: methodology-driven processing ─────────────────────────────
    ba_pairing = method_filter(
        BrandAssetPairing=1, OCR=None, IC=None, OCR_coordinates=None,
        BrandOnly=None, AssetOnly=None, Creative=None)
    finalResults1 = func.brand_asset_proc(ba_pairing, brandAssetResults, sport, iteration) \
        if not ba_pairing.empty else pd.DataFrame()

    ba_pairing_ocr = method_filter(
        BrandAssetPairing=1, OCR=1, IC=None, OCR_coordinates=None,
        BrandOnly=None, AssetOnly=None, Creative=None)
    finalResults2 = func.brand_asset_ocr_proc(ba_pairing_ocr, brandAssetResults, ocrResults, sport, iteration) \
        if not ba_pairing_ocr.empty else pd.DataFrame()

    ic_ba_pairing_ocr = method_filter(
        BrandAssetPairing=1, OCR=1, OCR_coordinates=None,
        BrandOnly=None, AssetOnly=None, Creative=None)
    ic_ba_pairing_ocr = ic_ba_pairing_ocr[ic_ba_pairing_ocr['IC'].notna()]
    finalResults3 = func.ic_brand_asset_ocr_proc(ic_ba_pairing_ocr, icResults, brandAssetResults, ocrResults, sport, iteration) \
        if not ic_ba_pairing_ocr.empty else pd.DataFrame()

    asset_only = method_filter(
        AssetOnly=1, BrandAssetPairing=None, OCR=None, IC=None,
        OCR_coordinates=None, BrandOnly=None, Creative=None)
    finalResults4 = func.asset_proc(asset_only, assetResults, sport, iteration) \
        if not asset_only.empty else pd.DataFrame()

    ic_asset = method_filter(
        AssetOnly=1, BrandAssetPairing=None, OCR=None,
        OCR_coordinates=None, BrandOnly=None, Creative=None)
    ic_asset = ic_asset[ic_asset['IC'].notna()]
    finalResults5 = func.ic_asset_proc(ic_asset, assetResults, icResults, sport, iteration) \
        if not ic_asset.empty else pd.DataFrame()

    brand_only = method_filter(
        BrandOnly=1, BrandAssetPairing=None, OCR=None, IC=None,
        OCR_coordinates=None, AssetOnly=None, Creative=None)
    finalResults6 = func.brand_proc(brand_only, brandResults, sport, iteration) \
        if not brand_only.empty else pd.DataFrame()

    ic_brand = method_filter(
        BrandOnly=1, BrandAssetPairing=None, OCR=None,
        OCR_coordinates=None, AssetOnly=None, Creative=None)
    ic_brand = ic_brand[ic_brand['IC'].notna()]
    finalResults7 = func.ic_brand_proc(ic_brand, brandResults, icResults, sport, iteration) \
        if not ic_brand.empty else pd.DataFrame()

    creative_ocr = method_filter(
        OCR=1, IC=None, OCR_coordinates=None, BrandAssetPairing=None,
        AssetOnly=None, BrandOnly=None)
    creative_ocr = creative_ocr[creative_ocr['Creative'].notna()]
    finalResults8 = func.creative_ocr_proc(creative_ocr, ocrResults, iteration) \
        if not creative_ocr.empty else pd.DataFrame()

    ic_creative_ocr = method_filter(
        OCR=1, OCR_coordinates=None, BrandAssetPairing=None,
        AssetOnly=None, BrandOnly=None)
    ic_creative_ocr = ic_creative_ocr[ic_creative_ocr['IC'].notna() & ic_creative_ocr['Creative'].notna()]
    finalResults9 = func.ic_creative_proc(ic_creative_ocr, ocrResults, icResults, sport, iteration) \
        if not ic_creative_ocr.empty else pd.DataFrame()

    ocr_only = method_filter(
        OCR=1, IC=None, Creative=None, BrandAssetPairing=None,
        OCR_coordinates=None, AssetOnly=None, BrandOnly=None)
    finalResults10 = func.ocr_proc(ocr_only, ocrResults, iteration) \
        if not ocr_only.empty else pd.DataFrame()

    ic_ocr = method_filter(
        OCR=1, Creative=None, BrandAssetPairing=None,
        OCR_coordinates=None, AssetOnly=None, BrandOnly=None)
    ic_ocr = ic_ocr[ic_ocr['IC'].notna()]
    finalResults11 = func.ic_ocr_proc(ic_ocr, ocrResults, icResults, sport, iteration) \
        if not ic_ocr.empty else pd.DataFrame()

    # ── Combine ───────────────────────────────────────────────────────────────
    finalResults_combined = pd.concat([
        finalResults0, finalResults1, finalResults2, finalResults3,
        finalResults4, finalResults5, finalResults6, finalResults7,
        finalResults8, finalResults9, finalResults10, finalResults11,
    ], ignore_index=True)

    # ── Missing OCR step ──────────────────────────────────────────────────────
    if missingOCRStep:
        final_output = func.missing_ocr_proc(
            brandAsset_method, ocrResults, assetResults, finalResults_combined,
            sport, iteration,
            brand_normalisation=brand_norm,
            valid_assets=valid_assets_list,
            brand_asset_corrections=corrections,
        )
        final_output = func.resolve_unassigned(
            final_output,
            icResults if not icResults.empty else pd.DataFrame(),
            unassigned_brand_asset_map,
            unassigned_ic_asset_map,
        )
    else:
        final_output = finalResults_combined

    if final_output.empty:
        return pd.DataFrame()

    # ── Final formatting ──────────────────────────────────────────────────────
    final_output['Filename'] = final_output['Filename'].str[-10:]
    final_output['Event']    = final_output['Event'].str.rstrip('/')

    final_output_v2 = func.update_screen_location(final_output, imageWidth, imageHeight)
    final_output_v3 = func.final_cleaning(final_output_v2, brandAsset_method)

    print(f"Exposure processing for {match} finished in {time.perf_counter() - start_time:.4f} seconds")
    return final_output_v3

# ============================================================================
# RUN ALL EVENTS
# ============================================================================

all_results = pd.DataFrame()
for eventName in listOfEvents:
    print(f"Processing: {eventName}")
    all_results = pd.concat([all_results, exposurePerEvent(eventName)], ignore_index=True)

all_results.to_csv(
    r'Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\Cricket\pls_ECB_WIT20_v2.csv',
    index=False
)

# ============================================================================
# UPLOAD TO SQL
# ============================================================================

def upload_to_sql(df, label='results'):
    """Upload a DataFrame to Toolkit_AzureModels_CombinedResults in chunks."""
    chunk_size = 10000
    chunks = np.array_split(df, max(1, len(df) // chunk_size))
    print(f"Uploading {label}: {len(df)} rows in {len(chunks)} chunks.")
    for i, chunk in enumerate(chunks):
        try:
            print(f"  Chunk {i+1}/{len(chunks)} ({len(chunk)} rows)...")
            lr.toSQL(chunk, sqlServer, sqlDatabase, 'Toolkit_AzureModels_CombinedResults')
            print(f"  Chunk {i+1} uploaded.")
        except Exception as e:
            print(f"  Error on chunk {i+1}: {e}. Stopping upload.")
            break
    print("Upload complete.")

if input("Upload all_results to Toolkit_AzureModels_CombinedResults? (Y/N): ").upper() == 'Y':
    upload_to_sql(all_results, 'all_results')
else:
    print('Results not uploaded.')

print(f"Total time: {time.perf_counter() - overall_start_time:.4f} seconds")
