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

sys.path.insert(0, r'Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\Post-Processing\WSL')
import SportsSight_functions_WSL as func



# ============================================================================
# CONFIGURATION
# ============================================================================

inputFile    = r"Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\Post-Processing\WSL\SportSight - Brand Asset Methodology - WSL_v6.xlsx"
output_folder = r"Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\Post-Processing\WSL"

sport       = 'wsl'
sqlServer   = 'inf'
sqlDatabase = 'WSL2'
iteration   = 'SS11'

# OCR coordinate tolerances (position/size relative to image; angle in degrees)
ocr_position_tolerance = 0.05
ocr_size_tolerance     = 0.2
ocr_angle_tolerance    = 5.0

listOfEvents = [
'BWSL_ARSvLCL_GW1',
'BWSL_BHAvAVL_GW1',
'BWSL_LIVvEVE_GW1',
'BWSL_MNUvLEI_GW1',
'BWSL_TOTvWHU_GW1',
'BWSL_MNCvBHA_GW2',
'BWSL_WHUvARS_GW2',
'BWSL_LCLvMNU_GW2',
'BWSL_LEIvLIV_GW2',
'BWSL_EVEvTH_GW2',
'BWSL_TOTvMNC_GW3',
'BWSL_EVEvLCL_GW3',
'BWSL_ASTvLIV_GW3',
'BWSL_BHAvWHU_GW3',
'BWSL_CHEvLEI_GW3',
'BSWL_MNUvARS_GW3',
'BWSL_ARSvAST_GW4',
'BWSL_BHAvEVE_GW4',
'BWSL_LEIvTOT_GW4',
'BWSL_LIVvMNU_GW4',
'BWSL_MNCvLCL_GW4',
'BWSL_WHUvCHE_GW4',
'BWSL_MNUvCHE_GW5',
'BWSL_MNCvARS_GW5',
'BWSL_WHUvAST_GW5',
'BWSL_LCLvLIV_GW5',
'BWSL_TOTvBHA_GW5',
'BWSL_LEIvEVE_GW5',
'BWSL_CHEvTOT_GW6',
'BWSL_LCLvWHU_GW6',
'BWSL_ARSvBHA_GW6',
'BWSL_ASTvLEI_GW6',
'BWSL_EVEvMNU_GW6',
'BWSL_LIVvMCI_GW6',
'BWSL_MNCvWHU_GW7',
'BWSL_ASTvEVE_GW7',
'BWSL_BHAvMNU_GW7',
'BWSL_CHEvLCL_GW7',
'BWSL_TOTvLIV_GW7',
'BWSL_LEIvARS_GW7',
'BWSL_ARSvCHE_GW8',
'BWSL_MNUvAST_GW8',
'BWSL_LCLvTOT_GW8',
'BWSL_WHUvLEI_GW8',
'BWSL_LIVvBHA_GW8',
'BWSL2_CharltonvPalace_GW1',
'BWSL2_ForestvNewcastle_GW1',
'BWSL2_PortsmouthvDurham_GW1',
'BWSL2_SouthamptonvIpswich_GW1',
'BWSL2_SheffieldvSunderland_GW1',
'BWSL2_BristolvPortsmouth_GW2',
'BWSL2_PalacevSouthampton_GW2',
'BWSL2_DurhamvCharlton_GW2',
'BWSL2_IpswichvForest_GW2',
'BWSL2_NewcastlevSheffield_GW2',
'BWSL2_SunderlandvBirmingham_GW2',
'BWSL2_PortsmouthvSheffield_GW3',
'BWSL2_BirminghamvNewcastle_GW3',
'BWSL2_CharltonvIpswich_GW3',
'BWSL2_SouthamptonvBristol_GW3',
'BWSL2_SunderlandvDurham_GW3',
'BWSL2_BristolvNottingham_GW4',
'BWSL2_DurhamvPalace_GW4',
'BWSL2_IpswichvPortsmouth_GW4',
'BWSL2_NewcastlevCharlton_GW4',
'BWSL2_SheffieldvBirmingham_GW4',
'BWSL2_SouthamptonvSunderland_GW4',
'BWSL2_BirminghamvSouthampton_GW5',
'BWSL2_BristolvDurham_GW5',
'BWSL2_PalacevNewcastle_GW5',
'BWSL2_ForestvPortsmouth_GW5',
'BWSL2_SheffieldvIpswich_GW5',
'BWSL2_SunderlandvCharlton_GW5',
'BWSL2_PortsmouthvSouthampton_GW6',
'BWSL2_CharltonvSheffield_GW6',
'BWSL2_PalacevSunderland_GW6',
'BWSL2_DurhamvForest_GW6',
'BWSL2_IpswichvBirmingham_GW6',
'BWSL2_NewcastlevBristol_GW6',
'BWSL2_PortsmouthvPalace_GW7',
'BWSL2_BirminghamvCharlton_GW7',
'BWSL2_IpswichvNewcastle_GW7',
'BWSL2_SheffieldvDurham_GW7',
'BWSL2_SouthamptonvForest_GW7',
'BWSL2_SunderlandvBristol_GW7',
'BWSL2_ForestvBirmingham_GW8',
'BWSL2_BristolvIpswich_GW8',
'BWSL2_CharltonvSouthampton_GW8',
'BWSL2_PalacevSheffield_GW8',
'BWSL2_DurhamvNewcastle_GW8',
'BWSL2_SunderlandvPortsmouth_GW8',
'BWSL2_SouthamptonvDurham_GW9',
'BWSL2_SheffieldvForest_GW9',
'BWSL2_NewcastlevSunderland_GW9',
'BWSL2_IpswichvPalace_GW9',
'BWSL2_CharltonvBristol_GW9',
'BWSL2_BirminghamvPortsmouth_GW9',
'BWSL2_DurhamvIpswich_GW10',
'BWSL2_NewcastlevSouthampton_GW10',
'BWSL2_BristolvSheffield_GW10',
'BWSL2_PortsmouthvCharlton_GW10',
'BWSL2_ForestvSunderland_GW10',
'BWSL2_SHUvSOT_GW11',
'BWSL2_SUNvIPS_GW11',
'BWSL2_CHAvNOT_GW11',
'BWSL2_BRCvPAL_GW11',
'BWSL2_BIRvDUR_GW11',
'BWSL2_PORvNEW_GW11',
'BWSL_WHUvEVE_GW9',
'BWSL_ASTvLCL_GW9',
'BWSL_BHAvLEI_GW9',
'BWSL_LIVvCHE_GW9',
'BWSL_TOTvARS_GW9',
'BWSL_MNCvMNU_GW9',
'BWSL_ARSvLIV_GW10',
'BWSL_MNUvWHU_GW10',
'BWSL_CHEvEVE_GW10',
'BWSL_LCLvBHA_GW10',
'BWSL_TOTvAST_GW10',
'BWSL_LEIvMNC_GW10',
'BWSL_WHUvLIV_GW11',
'BWSL_MNCvAST_GW11',
'BWSL_MNUvTOT_GW11',
'BWSL_BHAvCHE_GW11',
'BWSL_EVEvARS_GW11',
'BWSL_LEIvLCL_GW11',
'SWLC_LIVvSUN_GroupStage',
'SWLC_NEWvMCI_GroupStage',
'SWLC_SUNvDUR_GroupStage',
'SWLC_ASTvBIR_GroupStage',
'BWSL_ARSvMNU_GW12',
'BWSL_ASTvBHA_GW12',
'BWSL_CHEvWHU_GW12',
'BWSL_MNCvEVE_GW12',
'BWSL_TOTvLEI_GW12',
'BWSL_LIVvLCL_GW12',
'BWSL_EVEvBHA_GW13',
'BWSL_CHEvARS_GW13',
'BWSL_ASTvMNU_GW13',
'BWSL_LEIvWHU_GW13',
'BWSL_LIVvTOT_GW13',
'BWSL_LCLvMNC_GW13',
'BWSL_BHAvLCL_GW14',
'BWSL_EVEvAST_GW14',
'BWSL_MNUvLIV_GW14',
'BWSL_WHUvTOT_GW14',
'BWSL_MNCvCHE_GW14',
'BWSL_LEIvMNU_GW15',
'BWSL_ARSvMNC_GW15',
'BWSL_LIVvAST_GW15',
'BWSL_LCLvEVE_GW15',
'BWSL_WHU_BHA_GW15',
'BWSL_TOTvCHE_GW15',
'BWSL_MNCvLEI_GW16',
'BWSL_CHEvLIV_GW16',
'BWSL_MNUvLCL_GW16',
'BWSL_EVEvWHU_GW16',
'BWSL_ASTvTOT_GW16',
'BWSL_BHAvARS_GW16',
'BWSL_ASTvMNC_GW17',
'BWSL_LCLvARS_GW17',
'BWSL_TOTvEVE_GW17',
'BWSL_LIVvLEI_GW17',
'BWSL_CHEvBHA_GW17',
'BWSL_WHUvMNU_GW17',
'BWSL_ARSvWHU_GW18',
'BWSL_BHAvLIV_GW18',
'BWSL_LEIvAST_GW18',
'BWSL_LCLvCHE_GW18',
'BWSL_MNCvTOT_GW18',
'BWSL_MNUvEVE_GW18',
'BWSL_ARSvTOT_GW19',
'BWSL_CHEvAST_GW19',
'BWSL_EVEvLIV_GW19',
'BWSL_LEIvBHA_GW19',
'BWSL_MNUvMNC_GW19',
'BWSL_WHUvLCL_GW19',
'BWSL_ASTvARS_GW20',
'BWSL_BHAvMNC_GW20',
'BWSL_EVEvCHE_GW20',
'BWSL_LIVvWHU_GW20',
'BWSL_LCLvLEI_GW20',
'BWSL_TOTvMNU_GW20',
'BWSL_ARSvLEI_GW14',
'BWSL_ARSvEVE_GW21',
'BWSL_ASTvWHU_GW21',
'BWSL_LEIvCHE_GW21',
'BWSL_MNCvLIV_GW21',
'BWSL_MNUvBHA_GW21',
'BWSL_TOTvLCL_GW21',
'BWSL_BHAvTOT_GW22',
'BWSL_CHEvMNU_GW22',
'BWSL_EVEvLEI_GW22',
'BWSL_LIVvARS_GW22',
'BWSL_LCLvAST_GW22',
'BWSL_WHUvMNC_GW22',
'BWSL2_NOTvBRC_GW12',
'BWSL2_SheffieldvPalace_GW12',
'BWSL2_SouthamptonvPortsmouth_GW12',
'BWSL2_NottinghamvSheffield_GW13',
'BWSL2_PortsmouthvBirmingham_GW13',
'BWSL2_CharltonvNewcastle_GW13',
'BWSL2_PalacevDurham_GW13',
'BWSL2_IpswichvBristol_GW13',
'BWSL2_SunderlandvSouthampton_GW13',
'BWSL2_BirminghamvForest_GW14',
'BWSL2_BristolvSunderland_GW14',
'BWSL2_DurhamvPortsmouth_GW14',
'BWSL2_NewcastlevIpswich_GW14',
'BWSL2_SheffieldvCharlton_GW14',
'BWSL2_SouthamptonvPalace_GW14',
'BWSL2_ForestvCharlton_GW15',
'BWSL2_PalacevBristol_GW15',
'BWSL2_DurhamvBirmingham_GW15',
'BWSL2_PortsmouthvIpswich_GW15',
'BWSL2_SouthamptonvNewcastle_GW15',
'BWSL2_SunderlandvSheffield_GW15',
'BWSL2_BirminghamvPalace_GW16',
'BWSL2_BristolvSouthampton_GW16',
'BWSL2_CharltonvDurham_GW16',
'BWSL2_IpswichvSheffield_GW16',
'BWSL2_NewcastlevPortsmouth_GW16',
'BWSL2_SunderlandvNottingham_GW16',
'BWSL2_IpswichvCharlton_GW12',
'BWSL2_DurhamvSunderland_GW12',
'BWSL2_CharltonvSunderland_GW17',
'BWSL2_CrystalvForest_GW17',
'BWSL2_IpswichvDurham_GW17',
'BWSL2_PortsmouthvBristol_GW17',
'BWSL2_SheffieldvNewcastle_GW17',
'BWSL2_SouthamptonvBirmingham_GW17',
'BWSL2_NewcastlevBirmingham_GW12',
'BWSL2_NottinghamvIpswich_GW18',
'BWSL2_BirminghamvSheffield_GW18',
'BWSL2_BristolvCharlton_GW18',
'BWSL2_DurhamvSouthampton_GW18',
'BWSL2_NewcastlevPalace_GW18',
'BWSL2_PortsmouthvSunderland_GW18',
'BWSL2_NottinghamvDurham_GW19',
'BWSL2_BristolvBirmingham_GW19',
'BWSL2_PalacevCharlton_GW19',
'BWSL2_IpswichvSouthampton_GW19',
'BWSL2_SheffieldvPortsmouth_GW19',
'BWSL2_SunderlandvNewcastle_GW19',
'BWSL2_BirminghamvSunderland_GW20',
'BWSL2_CharltonvPortsmouth_GW20',
'BWSL2_DurhamvBristol_GW20',
'BWSL2_NewcastlevForest_GW20',
'BWSL2_SouthamptonvSheffield_GW20',
'BWSL2_BirminghamvIpswich_GW21',
'BWSL2_BristolvNewcastle_GW21',
'BWSL2_DurhamvSheffield_GW21',
'BWSL2_PortsmouthvForest_GW21',
'BWSL2_SouthamptonvCharlton_GW21',
'BWSL2_SunderlandvPalace_GW21',
'BWSL2_ForestvSouthampton_GW22',
'BWSL2_CharltonvBirmginham_GW22',
'BWSL2_PalacevPortsmouth_GW22',
'BWSL2_IpswichvSunderland_GW22',
'BWSL2_NewcastlevDurham_GW22',
'BWSL2_SheffieldvBristol_GW22',
'SWLC_LIVvCHE_QF',
'SWLC_CRYvARS_QF',
'SWLC_WHUvMNC_QF',
'SWLC_ARSvMNU_SF',
'SWLC_MNCvCHE_SF',
'BWSL_CharltonvLeicester_PlayOff',
'BWSL2_BirminghamvBristol_GW1',
'BWSL2_ForestvPalace_GW3',
'BWSL2_PalacevBirmingham_GW10',
'SWLC_MNUvTOT_QF'
]

missingOCRStep = True

# Brand normalisation for missing OCR step — set to None if not needed
brand_norm = {    'Barclays': 'Barclays_All',
    'Barclays WSL': 'Barclays_All',
    'Barclays Solus': 'Barclays_All' } # None

# Assets to include in missing OCR matching — set to None to include all
valid_assets_list = [
'Ball'
,'Ball Plinth'
,'Branded Walk Out Mat'
,'Broadcast Overlays'
,'Centre Circle Mat'
,'Club Sleeve Branding'
,'Corner Board'
,'Corner Flag'
,'Fourth Officials Board'
,'Goal Side Wedge'
,'Interview Backdrop'
,'Perimeter Board'
,'Referee Shirt Patch'
,'Team Line Up Handshake Boards'
]

# Brand corrections applied during missing OCR matching
corrections = [   {'asset': 'Club Sleeve Branding', 'normalised_brand': 'Barclays_All', 'corrected_brand': 'Barclays WSL'},
    {'asset': 'Broadcast overlays', 'normalised_brand': 'Barclays_All', 'corrected_brand': 'Barclays WSL'},
    {'asset': 'Goal-Side Wedge', 'normalised_brand': 'Barclays_All', 'corrected_brand': 'Barclays Solus'} ]

# Pass 1: Brand -> Asset for Unassigned rows
unassigned_brand_asset_map = {
    'Mercedes-Benz': 'Perimeter Board',
    'Mercedes':  'Perimeter Board'
}

# Pass 2: (IC prediction, Brand) -> Asset for still-Unassigned rows
unassigned_ic_asset_map = {
    ('Interview Backdrop',    'Barclays Solus'): 'Interview Backdrop',
    ('Interview Backdrop', 'Barclays WSL'):     'Interview Backdrop',
    ('Interview Backdrop',  'British Gas'):     'Interview Backdrop',
    ('Interview Backdrop',        'Sky'):     'Interview Backdrop',
    ('Player-Ref Close Up',       'Sky'):     'Corner Board',
    ('Player Walk Out',       'Sky'):     'Corner Board',
    ('Player-Ref Close Up',  'British Gas'):     'Perimenter Board',
    ('Dugout',  'British Gas'):     'Perimeter Board',
    ('Field Shot - Left - Zoom',  'British Gas'):     'Perimeter Board',
    ('Field Shot - Right - Zoom',  'British Gas'):     'Perimeter Board',
    ('Field Shot - Centre - Zoom',  'British Gas'):     'Perimeter Board',
    ('Player Walk Out',  'British Gas'):     'Perimeter Board',
    ('Field Shot - Centre - Zoom',  'Barclays WSL'):     'Perimeter Board',
    ('Field Shot - Centre - Zoom',  'Barclays Solus'):     'Perimeter Board'
}

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
            brands=['Barclays', 'Barclays WSL', 'Barclays Solus', 'Subway'],
            cleaned_text_list=['Barclays', 'Barclays WSL', 'Barclays Solus', 'Subway'],
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
    r'Z:\Shared\OCT\LDN\FSE\FSEData\Technology Team\Charlie Reed\SportsSight\pls_wsl2_5.csv',
    index=False
)


# ============================================================================
# Check for lines which may be a problem
# ============================================================================

all_results.isna().sum()

df_nan = all_results[all_results["ModelType"].isna()]

df_nan_2 = all_results[all_results["Filename"].isna()]

df_nan_3 = all_results[all_results["Event"].isna()]

# ============================================================================
# Delete all NA Lines
# ============================================================================

all_results = all_results[all_results["ModelType"].notna()]
all_results = all_results[all_results["Event"].notna()]

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
