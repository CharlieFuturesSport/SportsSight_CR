# -*- coding: utf-8 -*-
"""
Created on Thu Jan 15 10:18:38 2026
SportsSight_functions_HR

@author: Ernest.Teh
"""
import pandas as pd
import numpy as np
import uuid

# Mapping to X/Y coordinates
column_mapping = {
    'BoxTopLeftX': 'X1',
    'BoxTopLeftY': 'Y1',
    'BoxTopRightX': 'X2',
    'BoxTopRightY': 'Y2',
    'BoxBottomRightX': 'X3',
    'BoxBottomRightY': 'Y3',
    'BoxBottomLeftX': 'X4',
    'BoxBottomLeftY': 'Y4'
}

column_mapping_v2 = {
    'BrandTopLeftX': 'X1',
    'BrandTopLeftY': 'Y1',
    'BrandTopRightX': 'X2',
    'BrandTopRightY': 'Y2',
    'BrandBottomRightX': 'X3',
    'BrandBottomRightY': 'Y3',
    'BrandBottomLeftX': 'X4',
    'BrandBottomLeftY': 'Y4'
}

results_columns = [
    'ModelType', 'Guid_ID', 'Sport', 'Event', 'Filename', 'Brand', 'Asset',
    'X1', 'Y1', 'X2', 'Y2', 'X3', 'Y3', 'X4', 'Y4',
    'Probability', 'Iteration', 'AcceptedExposure', 'Original_Tag',
    'Original_BrandMessaging', 'Original_Asset', 'ScreenSize', 'ScreenLocation'
]

def calculate_iou_vectorized(boxes1, boxes2):
    boxes1 = boxes1[:, np.newaxis, :]
    boxes2 = boxes2[np.newaxis, :, :]
    
    x_left = np.maximum(boxes1[:, :, 0], boxes2[:, :, 0])
    y_top = np.maximum(boxes1[:, :, 1], boxes2[:, :, 1])
    x_right = np.minimum(boxes1[:, :, 2], boxes2[:, :, 2])
    y_bottom = np.minimum(boxes1[:, :, 3], boxes2[:, :, 3])
    
    intersection_width = np.maximum(0, x_right - x_left)
    intersection_height = np.maximum(0, y_bottom - y_top)
    intersection_area = intersection_width * intersection_height
    
    boxes1_area = (boxes1[:, :, 2] - boxes1[:, :, 0]) * (boxes1[:, :, 3] - boxes1[:, :, 1])
    boxes2_area = (boxes2[:, :, 2] - boxes2[:, :, 0]) * (boxes2[:, :, 3] - boxes2[:, :, 1])
    
    union_area = boxes1_area + boxes2_area - intersection_area
    # Use masked division so invalid divisions are never evaluated.
    iou = np.divide(
        intersection_area,
        union_area,
        out=np.zeros_like(intersection_area, dtype=float),
        where=union_area > 0,
    )
    
    return iou


def creative_ocr_proc(creative_ocr, ocrResults, iteration):
    modelType = 'Creative_OCR'
    
    if 'Brand2' not in creative_ocr.columns:
        creative_ocr = creative_ocr.copy()
        creative_ocr['Brand2'] = creative_ocr['Brand']
        
    creative_to_brand = dict(zip(creative_ocr['Brand2'], creative_ocr['Brand']))
    creative_to_asset = dict(zip(creative_ocr['Brand2'], creative_ocr['Asset']))
    
    filtered_ocr = ocrResults[
        ocrResults['cleaned_text'].isin(creative_ocr['Brand2'])
    ].copy()
    
    filtered_ocr['Original_Tag'] = filtered_ocr['cleaned_text']
    filtered_ocr['Brand'] = filtered_ocr['Original_Tag'].map(creative_to_brand)
    filtered_ocr['Asset'] = filtered_ocr['Original_Tag'].map(creative_to_asset)
    
    filtered_ocr['ModelType'] = modelType 
    filtered_ocr['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(filtered_ocr))]
    filtered_ocr = filtered_ocr.rename(columns={'SportsEvent': 'Event'})
    filtered_ocr['Event'] = filtered_ocr['Event']
    filtered_ocr['Filename'] = filtered_ocr['Filename'].str[-10:] 
    filtered_ocr = filtered_ocr.rename(columns={'original_text': 'Original_BrandMessaging'})
    filtered_ocr = filtered_ocr.rename(columns=column_mapping)
    filtered_ocr['Probability'] = 1
    filtered_ocr['Iteration'] = iteration
    filtered_ocr['AcceptedExposure'] = 1
    box_area = (filtered_ocr['X2'] - filtered_ocr['X1']).abs() * (filtered_ocr['Y4'] - filtered_ocr['Y1']).abs()
    screen_area = filtered_ocr['imageWidth'] * filtered_ocr['imageHeight']   
    filtered_ocr['ScreenSize'] = (box_area / screen_area)
    
    final_output = filtered_ocr.reindex(columns=results_columns)
    return final_output


def brand_asset_proc(ba_pairing, brandAssetResults, sport, iteration):
    modelType = 'Brand_Asset'
    event = brandAssetResults['SportsEvent']

    valid_pairings = ba_pairing[['Brand', 'Asset']].drop_duplicates()
    valid_pairing_set = set(zip(valid_pairings['Brand'], valid_pairings['Asset']))
    
    brandAssetResults_filtered = brandAssetResults[
        brandAssetResults.apply(lambda row: (row['Brand'], row['Asset']) in valid_pairing_set, axis=1)
    ].copy()
    
    merged = brandAssetResults_filtered.merge(
        ba_pairing[['Brand', 'Asset', 'Brand_confidence', 'Asset_confidence']],
        on=['Brand', 'Asset'],
        how='inner'
    )
    
    high_conf_ba = merged[
        (merged['BrandConfidence'] >= merged['Brand_confidence']) &
        (merged['AssetConfidence'] >= merged['Asset_confidence'])
    ].copy()
    
    high_conf_ba = high_conf_ba.drop(columns=['Brand_confidence', 'Asset_confidence'])
    
    high_conf_ba_full = high_conf_ba.copy()
    high_conf_ba_full['Source'] = 'High_Confidence_BA'
    high_conf_ba_full['Filename'] = high_conf_ba_full['Image'].str[-10:]
    
    high_conf_ba_full['BrandTopRightX']   = high_conf_ba_full['BrandBottomRightX']
    high_conf_ba_full['BrandTopRightY']   = high_conf_ba_full['BrandTopLeftY']
    high_conf_ba_full['BrandBottomLeftX'] = high_conf_ba_full['BrandTopLeftX']
    high_conf_ba_full['BrandBottomLeftY'] = high_conf_ba_full['BrandBottomRightY']
    
    high_conf_ba_full['ModelType'] = modelType 
    high_conf_ba_full['Sport'] = sport 
    high_conf_ba_full['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(high_conf_ba_full))]
    high_conf_ba_full = high_conf_ba_full.rename(columns={'SportsEvent': 'Event'})
    high_conf_ba_full['Event'] = event
    high_conf_ba_full = high_conf_ba_full.rename(columns=column_mapping_v2)
    high_conf_ba_full['Original_Tag'] = high_conf_ba_full['Source']
    high_conf_ba_full['Probability'] = high_conf_ba_full['AssetConfidence']
    high_conf_ba_full['Iteration'] = iteration
    high_conf_ba_full['AcceptedExposure'] = 1  
    high_conf_ba_full['ScreenSize'] = high_conf_ba_full['Box_Size_Perc']   
    high_conf_ba_full['ScreenLocation'] = None
    
    final_output = high_conf_ba_full.reindex(columns=results_columns)
    return final_output    


def brand_asset_ocr_proc(ba_pairing_ocr, brandAssetResults, ocrResults, sport, iteration): 
    modelType = 'Brand_Asset_OCR'
    event = brandAssetResults['SportsEvent']

    valid_pairings = ba_pairing_ocr[['Brand', 'Asset']].drop_duplicates()
    valid_pairing_set = set(zip(valid_pairings['Brand'], valid_pairings['Asset']))
    
    brandAssetResults_filtered = brandAssetResults[
        brandAssetResults.apply(lambda row: (row['Brand'], row['Asset']) in valid_pairing_set, axis=1)
    ].copy()
    
    def find_ba_ocr_overlaps(ba_results, ocr_results, iou_threshold=0.1):
        results = []
        
        ba_df = ba_results.copy()
        ba_df['Filename'] = ba_df['Image'].str[-10:]
        
        ocr_df = ocr_results.copy()
        ocr_df['Filename'] = ocr_df['Filename'].str[-10:]
        
        ba_grouped = ba_df.groupby(['Brand', 'Filename'])
        ocr_grouped = ocr_df.groupby(['Brand', 'Filename'])
        
        ba_keys = set(ba_grouped.groups.keys())
        ocr_keys = set(ocr_grouped.groups.keys())
        common_keys = ba_keys & ocr_keys
        
        print(f"Number of BA keys: {len(ba_keys)}")
        print(f"Number of OCR keys: {len(ocr_keys)}")
        print(f"Number of common keys: {len(common_keys)}")
          
        for brand, filename in common_keys:
            ba_group = ba_grouped.get_group((brand, filename))
            ocr_group = ocr_grouped.get_group((brand, filename))
            
            ba_boxes = ba_group[['BrandTopLeftX', 'BrandTopLeftY', 
                                 'BrandBottomRightX', 'BrandBottomRightY']].values
            ocr_boxes = ocr_group[['BoxTopLeftX', 'BoxTopLeftY', 
                                   'BoxBottomRightX', 'BoxBottomRightY']].values
            
            iou_matrix = calculate_iou_vectorized(ba_boxes, ocr_boxes)
            ba_indices, ocr_indices = np.where(iou_matrix >= iou_threshold)
            
            for ba_i, ocr_i in zip(ba_indices, ocr_indices):
                ba_row = ba_group.iloc[ba_i]
                ocr_row = ocr_group.iloc[ocr_i]
                
                results.append({
                    'Brand': brand,
                    'Filename': filename,
                    'BA_Image': ba_row['Image'],
                    'BA_Asset': ba_row['Asset'],
                    'BA_AssetConfidence': ba_row['AssetConfidence'],
                    'BA_BrandConfidence': ba_row['BrandConfidence'],
                    'TopLeftX':     ba_row['BrandTopLeftX'],
                    'TopLeftY':     ba_row['BrandTopLeftY'],
                    'TopRightX':    ba_row['BrandBottomRightX'],
                    'TopRightY':    ba_row['BrandTopLeftY'],
                    'BottomRightX': ba_row['BrandBottomRightX'],
                    'BottomRightY': ba_row['BrandBottomRightY'],
                    'BottomLeftX':  ba_row['BrandTopLeftX'],
                    'BottomLeftY':  ba_row['BrandBottomRightY'],
                    'Box_Size_Perc': ba_row['Box_Size_Perc'],
                    'OCR_Text': ocr_row['Brand'],
                    'IoU': iou_matrix[ba_i, ocr_i],
                })
        
        return pd.DataFrame(results)
    
    ba_ocr_overlaps = find_ba_ocr_overlaps(brandAssetResults_filtered, ocrResults, iou_threshold=0.1)    
    
    brandAssetResults_filtered['temp_id'] = (
        brandAssetResults_filtered['Image'].astype(str) + '_' + 
        brandAssetResults_filtered['Brand'].astype(str) + '_' + 
        brandAssetResults_filtered['Asset'].astype(str) + '_' +
        brandAssetResults_filtered['BrandTopLeftX'].astype(str) + '_' +
        brandAssetResults_filtered['BrandTopLeftY'].astype(str)
    )
    
    if ba_ocr_overlaps.empty or 'BA_Image' not in ba_ocr_overlaps.columns:
        print("Warning: No BA/OCR overlaps found. Continuing with high confidence BA only.")
        remaining_ba = brandAssetResults_filtered.copy()
        remaining_ba.drop(columns=['temp_id'], inplace=True)
        ba_ocr_full = pd.DataFrame()
    else:
        ba_ocr_overlaps['temp_id'] = (
            ba_ocr_overlaps['BA_Image'].astype(str) + '_' + 
            ba_ocr_overlaps['Brand'].astype(str) + '_' + 
            ba_ocr_overlaps['BA_Asset'].astype(str) + '_' +
            ba_ocr_overlaps['TopLeftX'].astype(str) + '_' +
            ba_ocr_overlaps['TopLeftY'].astype(str)
        )
        
        remaining_ba = brandAssetResults_filtered[
            ~brandAssetResults_filtered['temp_id'].isin(ba_ocr_overlaps['temp_id'])
        ].copy()
        
        brandAssetResults_filtered.drop(columns=['temp_id'], inplace=True)
        ba_ocr_overlaps.drop(columns=['temp_id'], inplace=True)
        remaining_ba.drop(columns=['temp_id'], inplace=True)
        
        ba_ocr_full = ba_ocr_overlaps.copy()
        ba_ocr_full['Source'] = 'BA_OCR_Overlap'
        ba_ocr_full = ba_ocr_full.rename(columns={
            'BA_Image': 'Image',
            'BA_Asset': 'Asset',
            'BA_AssetConfidence': 'AssetConfidence',
            'BA_BrandConfidence': 'BrandConfidence',
            'BA_Box': 'Model_Box'
        })

    merged = remaining_ba.merge(
        ba_pairing_ocr[['Brand', 'Asset', 'Brand_confidence', 'Asset_confidence']],
        on=['Brand', 'Asset'],
        how='inner'
    )
    
    high_conf_ba = merged[
        (merged['BrandConfidence'] >= merged['Brand_confidence']) &
        (merged['AssetConfidence'] >= merged['Asset_confidence'])
    ].copy()
    
    high_conf_ba = high_conf_ba.drop(columns=['Brand_confidence', 'Asset_confidence'])
    
    high_conf_ba_full = high_conf_ba.copy()
    high_conf_ba_full['Filename'] = high_conf_ba_full['Image'].str[-10:]
    
    high_conf_ba_full['TopLeftX']     = high_conf_ba_full['BrandTopLeftX']
    high_conf_ba_full['TopLeftY']     = high_conf_ba_full['BrandTopLeftY']
    high_conf_ba_full['TopRightX']    = high_conf_ba_full['BrandBottomRightX']
    high_conf_ba_full['TopRightY']    = high_conf_ba_full['BrandTopLeftY']
    high_conf_ba_full['BottomRightX'] = high_conf_ba_full['BrandBottomRightX']
    high_conf_ba_full['BottomRightY'] = high_conf_ba_full['BrandBottomRightY']
    high_conf_ba_full['BottomLeftX']  = high_conf_ba_full['BrandTopLeftX']
    high_conf_ba_full['BottomLeftY']  = high_conf_ba_full['BrandBottomRightY']

    if not ba_ocr_full.empty:
        ba_ocr_filenames = set(ba_ocr_full['Filename'])
        high_conf_ba_full['Source'] = np.where(
            high_conf_ba_full['Filename'].isin(ba_ocr_filenames),
            'High_Confidence_BA_Additional',
            'High_Confidence_BA_New'
        )
    else:
        high_conf_ba_full['Source'] = 'High_Confidence_BA_New'

    raw_dfs = [high_conf_ba_full, ba_ocr_full]
    valid_dfs = [df for df in raw_dfs if not df.empty]
    
    if len(valid_dfs) > 0:
        combined_ba = pd.concat(valid_dfs, ignore_index=True)
    else:
        print("Warning: No results found in brand_asset_ocr_proc. Returning empty.")
        return pd.DataFrame()
    
    # Ensure all rows have Brand* coordinate columns
    for src, dst in [('TopLeftX', 'BrandTopLeftX'), ('TopLeftY', 'BrandTopLeftY'),
                     ('TopRightX', 'BrandTopRightX'), ('TopRightY', 'BrandTopRightY'),
                     ('BottomRightX', 'BrandBottomRightX'), ('BottomRightY', 'BrandBottomRightY'),
                     ('BottomLeftX', 'BrandBottomLeftX'), ('BottomLeftY', 'BrandBottomLeftY')]:
        if dst not in combined_ba.columns:
            combined_ba[dst] = combined_ba[src]
        else:
            combined_ba[dst] = combined_ba[dst].fillna(combined_ba[src])

    combined_ba['ModelType'] = modelType 
    combined_ba['Sport'] = sport 
    combined_ba['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(combined_ba))]
    combined_ba = combined_ba.rename(columns={'SportsEvent': 'Event'})
    combined_ba['Event'] = event
    combined_ba['Filename'] = combined_ba['Filename'].str[-10:]
    combined_ba = combined_ba.rename(columns=column_mapping_v2)
    combined_ba['Original_BrandMessaging'] = combined_ba['OCR_Text']
    combined_ba['Original_Tag'] = combined_ba['Source']
    combined_ba['Probability'] = combined_ba['BrandConfidence']
    combined_ba['Iteration'] = iteration
    combined_ba['AcceptedExposure'] = 1  
    combined_ba['ScreenSize'] = combined_ba['Box_Size_Perc']   
    combined_ba['ScreenLocation'] = None
    
    final_output = combined_ba.reindex(columns=results_columns)
    return final_output


def ic_brand_asset_ocr_proc(ic_ba_pairing_ocr, icResults, brandAssetResults, ocrResults, sport, iteration):
    modelType = 'IC_Brand_Asset_OCR'
    
    ic_ba_pairing_ocr['IC'] = ic_ba_pairing_ocr['IC'].str.split(', ')
    ic_ba_pairing_ocr = ic_ba_pairing_ocr.explode('IC')
    ic_ba_pairing_ocr = ic_ba_pairing_ocr.dropna(subset=['IC'])
    ic_ba_pairing_ocr['IC'] = ic_ba_pairing_ocr['IC'].str.strip()
    ic_ba_pairing_ocr = ic_ba_pairing_ocr.reset_index(drop=True)
    
    ba_ocr_results = brand_asset_ocr_proc(ic_ba_pairing_ocr, brandAssetResults, ocrResults, sport, iteration)

    if ba_ocr_results.empty:
        return pd.DataFrame(columns=results_columns)
    
    icResults = icResults.rename(columns={'Image': 'Filename', 'Prediction': 'IC'})

    sample = ba_ocr_results['Filename'].iloc[0]
    if len(sample) <= 10:
        icResults['Filename'] = icResults['Filename'].str[-10:]
    
    ic_ba_ocr_results = ba_ocr_results.merge(icResults, on='Filename', how='left')

    merged_df = ic_ba_ocr_results.merge(
        ic_ba_pairing_ocr[['Brand', 'Asset', 'IC', 'IC_confidence']], 
        on=['Brand', 'Asset', 'IC'], 
        how='inner')
    
    merged_df = merged_df.drop_duplicates(subset=['Guid_ID'])
    
    final_filtered_results = merged_df[
        merged_df['Confidence'] >= merged_df['IC_confidence']
    ].copy()
    
    final_filtered_results['Original_Tag'] = final_filtered_results['IC']
    final_filtered_results['ModelType'] = modelType
    final_filtered_results['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(final_filtered_results))]
    final_filtered_results = final_filtered_results.drop(columns=['IC_confidence', 'SportsEvent', 'Id', 'IC'])
    final_filtered_results = final_filtered_results.reindex(columns=results_columns)
        
    return final_filtered_results


def asset_proc(asset, assetResults, sport, iteration):
    modelType = 'Asset'
    
    filtered_a = assetResults[
        assetResults['Asset'].isin(asset['Asset'])
    ].copy()
    
    merged = filtered_a.merge(
        asset[['Brand', 'Asset', 'Asset_confidence', 'MinSize']],
        on=['Asset'],
        how='inner'
    )
    
    filtered_a2 = merged[
        (merged['Box_Size_Perc'] >= merged['MinSize']) &
        (merged['Confidence'] >= merged['Asset_confidence'])
    ].copy()
    
    filtered_a2 = filtered_a2.drop(columns=['MinSize', 'Asset_confidence'])
    
    filtered_a2['X1'] = filtered_a2['TopLeftX']
    filtered_a2['Y1'] = filtered_a2['TopLeftY']
    filtered_a2['X3'] = filtered_a2['BottomRightX']
    filtered_a2['Y3'] = filtered_a2['BottomRightY']
    filtered_a2['X2'] = filtered_a2['X3']
    filtered_a2['Y2'] = filtered_a2['Y1']
    filtered_a2['X4'] = filtered_a2['X1']
    filtered_a2['Y4'] = filtered_a2['Y3']
    
    filtered_a2['ModelType'] = modelType 
    filtered_a2['Sport'] = sport 
    filtered_a2['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(filtered_a2))]
    filtered_a2 = filtered_a2.rename(columns={'SportsEvent': 'Event', 'Image': 'Filename'})
    filtered_a2['Event'] = filtered_a2['Event']
    filtered_a2['Filename'] = filtered_a2['Filename'].str[-10:] 
    filtered_a2['Probability'] = filtered_a2['Confidence']
    filtered_a2['Iteration'] = iteration
    filtered_a2['AcceptedExposure'] = 1
    filtered_a2['ScreenSize'] = filtered_a2['Box_Size_Perc']
    
    final_output = filtered_a2.reindex(columns=results_columns)
    return final_output


def brand_proc(brand, brandResults, sport, iteration):
    modelType = 'Brand'
    
    filtered_b = brandResults[
        brandResults['Brand'].isin(brand['Brand'])
    ].copy()
    
    merged = filtered_b.merge(
        brand[['Brand', 'Asset', 'Brand_confidence', 'MinSize']],
        on=['Brand'],
        how='inner'
    )
    
    filtered_b2 = merged[
        (merged['Box_Size_Perc'] >= merged['MinSize']) &
        (merged['BrandConfidence'] >= merged['Brand_confidence'])
    ].copy()
    
    filtered_b2 = filtered_b2.drop(columns=['MinSize', 'Brand_confidence'])
    
    filtered_b2['ModelType'] = modelType 
    filtered_b2['Sport'] = sport 
    filtered_b2['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(filtered_b2))]
    filtered_b2 = filtered_b2.rename(columns={'SportsEvent': 'Event', 'Image': 'Filename'})
    filtered_b2 = filtered_b2.rename(columns=column_mapping_v2)
    filtered_b2['Event'] = filtered_b2['Event']
    filtered_b2['Filename'] = filtered_b2['Filename'].str[-10:] 
    filtered_b2['Probability'] = filtered_b2['BrandConfidence']
    filtered_b2['Iteration'] = iteration
    filtered_b2['AcceptedExposure'] = 1
    filtered_b2['ScreenSize'] = filtered_b2['Box_Size_Perc']
    
    final_output = filtered_b2.reindex(columns=results_columns)
    return final_output


def ic_asset_proc(ic_asset, assetResults, icResults, sport, iteration):
    modelType = 'IC_Asset'
    
    ic_asset['IC'] = ic_asset['IC'].str.split(', ')
    ic_asset = ic_asset.explode('IC')
    ic_asset['IC'] = ic_asset['IC'].str.strip()
    ic_asset = ic_asset.reset_index(drop=True)
    
    asset_results = asset_proc(ic_asset, assetResults, sport, iteration)
    
    icResults = icResults.rename(columns={'Image': 'Filename', 'IC_tag': 'IC'})
    
    ic_asset_results = asset_results.merge(icResults, on='Filename', how='left')
    
    merged_df = ic_asset_results.merge(
        ic_asset[['Brand', 'Asset', 'IC', 'IC_confidence']], 
        on=['Brand', 'Asset', 'IC'], 
        how='inner')
    
    final_filtered_results = merged_df[
        merged_df['Confidence'] >= merged_df['IC_confidence']
    ].copy()
    
    final_filtered_results['Original_Tag'] = final_filtered_results['IC']
    final_filtered_results['ModelType'] = modelType
    final_filtered_results['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(final_filtered_results))]
    final_filtered_results = final_filtered_results.drop(columns=['IC_confidence', 'SportsEvent', 'Id', 'IC'])
    final_filtered_results = final_filtered_results.reindex(columns=results_columns)
       
    return final_filtered_results


def ic_brand_proc(ic_brand, brandResults, icResults, sport, iteration):
    modelType = 'IC_Brand'
    
    ic_brand['IC'] = ic_brand['IC'].str.split(', ')
    ic_brand = ic_brand.explode('IC')
    ic_brand['IC'] = ic_brand['IC'].str.strip()
    ic_brand = ic_brand.reset_index(drop=True)
    
    brand_results = brand_proc(ic_brand, brandResults, sport, iteration)
    
    icResults = icResults.rename(columns={'Image': 'Filename', 'IC_tag': 'IC'})
    
    ic_brand_results = brand_results.merge(icResults, on='Filename', how='left')
    
    merged_df = ic_brand_results.merge(
        ic_brand[['Brand', 'Asset', 'IC', 'IC_confidence']], 
        on=['Brand', 'Asset', 'IC'], 
        how='inner')
    
    final_filtered_results = merged_df[
        merged_df['Confidence'] >= merged_df['IC_confidence']
    ].copy()
    
    final_filtered_results['Original_Tag'] = final_filtered_results['IC']
    final_filtered_results['ModelType'] = modelType
    final_filtered_results['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(final_filtered_results))]
    final_filtered_results = final_filtered_results.drop(columns=['IC_confidence', 'SportsEvent', 'Id', 'IC'])
    final_filtered_results = final_filtered_results.reindex(columns=results_columns)
       
    return final_filtered_results


def ic_creative_proc(ic_creative_ocr, ocrResults, icResults, sport, iteration):
    modelType = 'IC_Creative_OCR'
    
    ic_creative_ocr['IC'] = ic_creative_ocr['IC'].str.split(', ')
    ic_creative_ocr = ic_creative_ocr.explode('IC')
    ic_creative_ocr['IC'] = ic_creative_ocr['IC'].str.strip()
    ic_creative_ocr = ic_creative_ocr.reset_index(drop=True)
    
    creative_results = creative_ocr_proc(ic_creative_ocr, ocrResults, iteration)
    
    icResults = icResults.rename(columns={'Image': 'Filename', 'IC_tag': 'IC'})
    
    ic_creative_results = creative_results.merge(icResults, on='Filename', how='left')
    
    merged_df = ic_creative_results.merge(
        ic_creative_ocr[['Brand', 'Asset', 'IC', 'IC_confidence']], 
        on=['Brand', 'Asset', 'IC'], 
        how='inner')
    
    final_filtered_results = merged_df[
        merged_df['Confidence'] >= merged_df['IC_confidence']
    ].copy()
    
    final_filtered_results['Original_Tag'] = final_filtered_results['IC']
    final_filtered_results['ModelType'] = modelType
    final_filtered_results['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(final_filtered_results))]
    final_filtered_results['Probability'] = final_filtered_results['Confidence']
    final_filtered_results = final_filtered_results.drop(columns=['IC_confidence', 'SportsEvent', 'Id', 'IC'])
    final_filtered_results = final_filtered_results.reindex(columns=results_columns)
       
    return final_filtered_results


def ocr_proc(ocr, ocrResults, iteration):
    modelType = 'OCR'
        
    filtered_ocr = ocrResults[
        ocrResults['Brand'].isin(ocr['Brand'])
    ].copy()
    
    filtered_ocr = filtered_ocr.drop(columns=['Asset'], errors='ignore')

    if filtered_ocr.empty or 'Filename' not in filtered_ocr.columns:
        print(f"Warning: No OCR results after filtering in ocr_proc. Returning empty.")
        return pd.DataFrame()
    
    filtered_ocr = filtered_ocr.merge(
        ocr[['Brand', 'Asset']], 
        on='Brand', 
        how='left'
    )
    
    filtered_ocr['ModelType'] = modelType 
    filtered_ocr['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(filtered_ocr))]
    filtered_ocr = filtered_ocr.rename(columns={'SportsEvent': 'Event'})
    filtered_ocr['Event'] = filtered_ocr['Event']
    filtered_ocr['Filename'] = filtered_ocr['Filename'].str[-10:] 
    filtered_ocr = filtered_ocr.rename(columns={'original_text': 'Original_BrandMessaging'})
    filtered_ocr = filtered_ocr.rename(columns=column_mapping)
    filtered_ocr['Probability'] = 1
    filtered_ocr['Iteration'] = iteration
    filtered_ocr['AcceptedExposure'] = 1
    box_area = (filtered_ocr['X2'] - filtered_ocr['X1']).abs() * (filtered_ocr['Y4'] - filtered_ocr['Y1']).abs()
    screen_area = filtered_ocr['imageWidth'] * filtered_ocr['imageHeight']   
    filtered_ocr['ScreenSize'] = (box_area / screen_area)
    
    final_output = filtered_ocr.reindex(columns=results_columns)
    return final_output


def ic_ocr_proc(ic_ocr, ocrResults, icResults, sport, iteration):
    modelType = 'IC_OCR'
    
    ic_ocr['IC'] = ic_ocr['IC'].str.split(', ')
    ic_ocr = ic_ocr.explode('IC')
    ic_ocr['IC'] = ic_ocr['IC'].str.strip()
    ic_ocr = ic_ocr.reset_index(drop=True)
    
    ocr_results = ocr_proc(ic_ocr, ocrResults, iteration)
    
    if ocr_results.empty:
        print(f"Warning: ocr_proc returned no results in ic_ocr_proc. Skipping.")
        return pd.DataFrame()
    
    icResults = icResults.rename(columns={'Image': 'Filename', 'IC_tag': 'IC'})
    
    ic_ocr_results = ocr_results.merge(icResults, on='Filename', how='left')
    
    merged_df = ic_ocr_results.merge(
        ic_ocr[['Brand', 'Asset', 'IC', 'IC_confidence']], 
        on=['Brand', 'Asset', 'IC'], 
        how='inner')
    
    final_filtered_results = merged_df[
        merged_df['Confidence'] >= merged_df['IC_confidence']
    ].copy()
    
    final_filtered_results['Original_Tag'] = final_filtered_results['IC']
    final_filtered_results['ModelType'] = modelType
    final_filtered_results['Guid_ID'] = [uuid.uuid4().hex for _ in range(len(final_filtered_results))]
    final_filtered_results = final_filtered_results.drop(columns=['IC_confidence', 'SportsEvent', 'Id', 'IC'])
    final_filtered_results = final_filtered_results.reindex(columns=results_columns)
       
    return final_filtered_results


def missing_ocr_proc(brandAsset_method, ocrResults, assetResults, finalResults_combined, sport, iteration, 
                     brand_normalisation=None, valid_assets=None, brand_asset_corrections=None):
    modelType = 'Missing_OCR'
    
    ocr_normalised = ocrResults.copy()
    
    if ocr_normalised.empty or 'Filename' not in ocr_normalised.columns:
        print("Warning: No OCR data in missing_ocr_proc. Skipping.")
        return pd.DataFrame()
    
    ocr_normalised['Filename_norm'] = ocr_normalised['Filename'].str[-10:]
    
    if brand_normalisation:
        ocr_normalised['Brand_Generic'] = ocr_normalised['Brand'].map(
            lambda x: brand_normalisation.get(x, x)
        )
    else:
        ocr_normalised['Brand_Generic'] = ocr_normalised['Brand']

    final_normalised = finalResults_combined.copy()
    final_normalised['Filename_norm'] = final_normalised['Filename'].str[-10:]
    
    if brand_normalisation:
        final_normalised['Brand_Generic'] = final_normalised['Brand'].map(
            lambda x: brand_normalisation.get(x, x)
        )
    else:
        final_normalised['Brand_Generic'] = final_normalised['Brand']

    ocr_combinations   = ocr_normalised[['Filename_norm', 'Brand_Generic']].drop_duplicates()
    final_combinations = final_normalised[['Filename_norm', 'Brand_Generic']].drop_duplicates()

    ocr_combinations['combo']   = list(zip(ocr_combinations['Filename_norm'],   ocr_combinations['Brand_Generic']))
    final_combinations['combo'] = list(zip(final_combinations['Filename_norm'], final_combinations['Brand_Generic']))

    missing_combos = ocr_combinations[
        ~ocr_combinations['combo'].isin(final_combinations['combo'])
    ].copy().drop(columns=['combo'])

    missing_details = ocr_normalised.merge(missing_combos, on=['Filename_norm', 'Brand_Generic'], how='inner')

    def calculate_center_distance(box1_coords, box2_coords):
        center1_x = (box1_coords[0] + box1_coords[2]) / 2
        center1_y = (box1_coords[1] + box1_coords[3]) / 2
        center2_x = (box2_coords[0] + box2_coords[2]) / 2
        center2_y = (box2_coords[1] + box2_coords[3]) / 2
        return np.sqrt((center1_x - center2_x)**2 + (center1_y - center2_y)**2)

    def match_missing_to_assets(missing_details, assetResults):
        if assetResults.empty or 'Image' not in assetResults.columns:
            print("Warning: No asset results available for missing OCR matching. Skipping.")
            return pd.DataFrame()

        results  = []
        missing_df = missing_details.copy()
        asset_df   = assetResults.copy()
        
        asset_df['Filename_norm'] = asset_df['Image'].str[-10:]
        asset_df['Width']  = asset_df['BottomRightX'] - asset_df['TopLeftX']
        asset_df['Height'] = asset_df['BottomRightY'] - asset_df['TopLeftY'] 
        
        missing_grouped = missing_df.groupby('Filename_norm')
        asset_grouped   = asset_df.groupby('Filename_norm')
        common_files    = set(missing_grouped.groups.keys()) & set(asset_grouped.groups.keys())
        
        for filename in common_files:
            missing_group = missing_grouped.get_group(filename)
            asset_group   = asset_grouped.get_group(filename)
            
            for idx, ocr_row in missing_group.iterrows():
                ocr_box = np.array([[
                    ocr_row['BoxTopLeftX'], ocr_row['BoxTopLeftY'],
                    ocr_row['BoxBottomRightX'], ocr_row['BoxBottomRightY']
                ]])
                
                asset_boxes_array = asset_group[['TopLeftX', 'TopLeftY', 'BottomRightX', 'BottomRightY']].values
                iou_scores = calculate_iou_vectorized(ocr_box, asset_boxes_array)[0]
                
                ocr_coords = (ocr_row['BoxTopLeftX'], ocr_row['BoxTopLeftY'], 
                              ocr_row['BoxBottomRightX'], ocr_row['BoxBottomRightY'])
                
                distances = [
                    calculate_center_distance(
                        ocr_coords,
                        (r['TopLeftX'], r['TopLeftY'], r['BottomRightX'], r['BottomRightY'])
                    )
                    for _, r in asset_group.iterrows()
                ]
                
                max_dist           = max(distances) if max(distances) > 0 else 1
                norm_distances     = [1 - (d / max_dist) for d in distances]
                combined_scores    = (
                    0.3 * iou_scores + 
                    0.5 * asset_group['Confidence'].values + 
                    0.2 * np.array(norm_distances)
                )
                
                best_idx   = np.argmax(combined_scores)
                best_asset = asset_group.iloc[best_idx]
                
                results.append({
                    'Filename':        filename,
                    'OCR_ID':          ocr_row['ID'],
                    'OCR_Brand':       ocr_row['Brand'],
                    'OCR_Brand_Generic': ocr_row['Brand_Generic'],
                    'OCR_Asset':       ocr_row['Asset'] if 'Asset' in ocr_row.index else None,
                    'OCR_Creative':    ocr_row['Creative'] if 'Creative' in ocr_row.index else None,
                    'OCR_Text':        ocr_row['Brand'],
                    'TopLeftX':        ocr_row['BoxTopLeftX'],
                    'TopLeftY':        ocr_row['BoxTopLeftY'],
                    'TopRightX':       ocr_row['BoxTopRightX'],
                    'TopRightY':       ocr_row['BoxTopRightY'],
                    'BottomRightX':    ocr_row['BoxBottomRightX'],
                    'BottomRightY':    ocr_row['BoxBottomRightY'],
                    'BottomLeftX':     ocr_row['BoxBottomLeftX'],
                    'BottomLeftY':     ocr_row['BoxBottomLeftY'],
                    'Box_Size_Perc':   ocr_row['Box_Size_Perc'],
                    'Matched_Asset':   best_asset['Asset'],
                    'Asset_Confidence': best_asset['Confidence'],
                    'IoU':             iou_scores[best_idx],
                    'Center_Distance': distances[best_idx],
                    'Combined_Score':  combined_scores[best_idx],
                    'OCR_Box':         f"({ocr_row['BoxTopLeftX']}, {ocr_row['BoxTopLeftY']}) - ({ocr_row['BoxBottomRightX']}, {ocr_row['BoxBottomRightY']})",
                    'Asset_Box':       f"({best_asset['TopLeftX']}, {best_asset['TopLeftY']}) - ({best_asset['BottomRightX']}, {best_asset['BottomRightY']})",
                    'SportsEvent':     ocr_row.get('SportsEvent', best_asset.get('SportsEvent', None))
                })
        
        return pd.DataFrame(results)

    matched_results = match_missing_to_assets(missing_details, assetResults)

    if matched_results.empty:
        print("Warning: No matched results from missing OCR step. Returning existing results.")
        return finalResults_combined
    
    if valid_assets:
        matched_results = matched_results[matched_results['Matched_Asset'].isin(valid_assets)].copy()
    
    if brand_asset_corrections:
        for correction in brand_asset_corrections:
            mask = (
                (matched_results['Matched_Asset']     == correction['asset']) &
                (matched_results['OCR_Brand_Generic'] == correction['normalised_brand'])
            )
            matched_results.loc[mask, 'OCR_Brand'] = correction['corrected_brand']
    
    comparison_df = matched_results.merge(
        brandAsset_method, 
        left_on=['OCR_Brand', 'Matched_Asset'], 
        right_on=['Brand', 'Asset'], 
        how='left',
        indicator=True
    )

    final_valid_matches = comparison_df[comparison_df['_merge'] == 'both'].copy()
    final_valid_matches = final_valid_matches.drop(columns=['Brand', 'Asset', '_merge'])
    final_valid_matches = final_valid_matches.rename(columns={'OCR_Brand': 'Brand', 'Matched_Asset': 'Asset'})

    final_valid_matches['ModelType']        = modelType 
    final_valid_matches['Sport']            = sport 
    final_valid_matches['Guid_ID']          = [uuid.uuid4().hex for _ in range(len(final_valid_matches))]
    final_valid_matches                     = final_valid_matches.rename(columns={'SportsEvent': 'Event'})
    final_valid_matches['Event']            = final_valid_matches['Event']
    final_valid_matches['Filename']         = final_valid_matches['Filename'].str[-10:]
    final_valid_matches                     = final_valid_matches.rename(columns={'OCR_Text': 'Original_BrandMessaging'})
    final_valid_matches                     = final_valid_matches.rename(columns={
        'TopLeftX': 'BrandTopLeftX', 'TopLeftY': 'BrandTopLeftY',
        'TopRightX': 'BrandTopRightX', 'TopRightY': 'BrandTopRightY',
        'BottomRightX': 'BrandBottomRightX', 'BottomRightY': 'BrandBottomRightY',
        'BottomLeftX': 'BrandBottomLeftX', 'BottomLeftY': 'BrandBottomLeftY',
    })
    final_valid_matches                     = final_valid_matches.rename(columns=column_mapping_v2)
    final_valid_matches['Probability']      = final_valid_matches['Asset_Confidence']
    final_valid_matches['Iteration']        = iteration
    final_valid_matches['AcceptedExposure'] = 1 
    final_valid_matches['ScreenSize']       = final_valid_matches['Box_Size_Perc']
    final_valid_matches['ScreenLocation']   = None
    
    final_valid_matches = final_valid_matches.loc[:, ~final_valid_matches.columns.duplicated()]
    final_valid_matches_format = final_valid_matches.reindex(columns=results_columns)
    
    matches_check   = final_valid_matches[['Filename', 'OCR_Brand_Generic']].rename(columns={'OCR_Brand_Generic': 'Brand_Generic'})
    missing_details = missing_details.drop(columns=['Filename']).rename(columns={'Filename_norm': 'Filename'})
    
    creative_ocr     = brandAsset_method[brandAsset_method['Creative'].notna() & (brandAsset_method['OCR'] == 1)].copy()
    brands_to_remove = creative_ocr['Creative'].unique()
    missing_details  = missing_details[~missing_details['Brand'].isin(brands_to_remove)].copy()
    
    comparison = missing_details.merge(
        matches_check, on=['Filename', 'Brand_Generic'], how='left', indicator=True
    )

    results_not_in_matches = comparison[comparison['_merge'] == 'left_only'].drop(columns=['_merge'])
    
    results_not_in_matches['Asset']             = 'Unassigned'
    results_not_in_matches['ModelType']         = modelType 
    results_not_in_matches['Sport']             = sport 
    results_not_in_matches['Guid_ID']           = [uuid.uuid4().hex for _ in range(len(results_not_in_matches))] # results_not_in_matches['OCRLineID'] 
    results_not_in_matches                      = results_not_in_matches.rename(columns={'SportsEvent': 'Event'})
    results_not_in_matches['Event']             = results_not_in_matches['Event']
    results_not_in_matches['Filename']          = results_not_in_matches['Filename'].str[-10:] 
    results_not_in_matches                      = results_not_in_matches.rename(columns={'original_text': 'Original_BrandMessaging'})
    results_not_in_matches                      = results_not_in_matches.rename(columns=column_mapping)
    results_not_in_matches['Probability']       = 1
    results_not_in_matches['Iteration']         = iteration
    results_not_in_matches['AcceptedExposure']  = 1 
    results_not_in_matches['ScreenSize']        = results_not_in_matches['Box_Size_Perc']
    results_not_in_matches['ScreenLocation']    = None 
    
    results_not_in_matches = results_not_in_matches.loc[:, ~results_not_in_matches.columns.duplicated()]
    unassigned_OCR = results_not_in_matches.reindex(columns=results_columns)
    
    return pd.concat([finalResults_combined, final_valid_matches_format, unassigned_OCR], ignore_index=True)


def resolve_unassigned(finalResults, icResults, brand_asset_map, ic_asset_map):
    if finalResults.empty:
        return finalResults

    df = finalResults.copy()
    unassigned_mask = df['Asset'] == 'Unassigned'

    if not unassigned_mask.any():
        return df

    # ------------------------------------------------------------------
    # Build best IC lookup upfront — used by both Pass 2 and Pass 3
    # ------------------------------------------------------------------
    best_ic = pd.DataFrame()

    if not icResults.empty:
        ic_df = icResults.copy()

        if 'Image' in ic_df.columns and 'Filename' not in ic_df.columns:
            ic_df = ic_df.rename(columns={'Image': 'Filename'})
        if 'Prediction' not in ic_df.columns and 'IC' in ic_df.columns:
            ic_df = ic_df.rename(columns={'IC': 'Prediction'})

        ic_df['Filename'] = ic_df['Filename'].str[-10:]

        best_ic = (
            ic_df.sort_values('Confidence', ascending=False)
                 .drop_duplicates(subset=['Filename'])
                 [['Filename', 'Prediction']]
        )

    # ------------------------------------------------------------------
    # Pass 1: Brand -> Asset direct mapping
    # ------------------------------------------------------------------
    if brand_asset_map:
        df.loc[unassigned_mask, 'Asset'] = (
            df.loc[unassigned_mask, 'Brand']
              .map(lambda b: brand_asset_map.get(b, 'Unassigned'))
        )

    unassigned_mask = df['Asset'] == 'Unassigned'

    if not unassigned_mask.any():
        return df

    # ------------------------------------------------------------------
    # Pass 2: (IC prediction, Brand) -> Asset mapping
    # ------------------------------------------------------------------
    if not best_ic.empty and ic_asset_map:
        still_unassigned_idx = df[unassigned_mask].index
        still_unassigned = df.loc[still_unassigned_idx, ['Filename', 'Brand']].copy()
        still_unassigned = still_unassigned.merge(best_ic, on='Filename', how='left')

        still_unassigned['IC_Asset'] = still_unassigned.apply(
            lambda row: ic_asset_map.get((row['Prediction'], row['Brand']), np.nan),
            axis=1
        )

        df.loc[still_unassigned_idx, 'Asset'] = np.where(
            still_unassigned['IC_Asset'].notna(),
            still_unassigned['IC_Asset'].values,
            df.loc[still_unassigned_idx, 'Asset'].values
        )

        resolved_count = (df.loc[still_unassigned_idx, 'Asset'] != 'Unassigned').sum()
        print(f"resolve_unassigned pass 2: {resolved_count} rows resolved via IC+Brand mapping.")

    # Recalculate after pass 2
    unassigned_mask = df['Asset'] == 'Unassigned'

    if not unassigned_mask.any():
        return df

    # ------------------------------------------------------------------
    # Pass 3: For rows still Unassigned, stamp Original_Tag with the
    #         best IC prediction for that filename so it is identifiable
    #         in SQL even though Asset remains 'Unassigned'
    # ------------------------------------------------------------------
    if not best_ic.empty:
        still_unassigned_idx = df[unassigned_mask].index
        still_unassigned = df.loc[still_unassigned_idx, ['Filename']].copy()
        still_unassigned = still_unassigned.merge(best_ic, on='Filename', how='left')

        has_prediction = still_unassigned['Prediction'].notna().values

        df.loc[
            still_unassigned_idx[has_prediction],
            'Original_Tag'
        ] = still_unassigned.loc[has_prediction, 'Prediction'].values
        
        df.loc[still_unassigned_idx[has_prediction], 'ModelType'] = 'Missing_OCR_Manual'

        stamped_count = has_prediction.sum()
        print(f"resolve_unassigned pass 3: {stamped_count} still-Unassigned rows had "
              f"Original_Tag stamped with best IC prediction.")
    else:
        print("resolve_unassigned pass 3: No IC results available to stamp Original_Tag.")

    print(f"resolve_unassigned complete: {(df['Asset'] == 'Unassigned').sum()} rows remain Unassigned.")

    return df


def update_screen_location(finalResults, imageWidth, imageHeight):
    cx = finalResults['X1'] + (np.abs(finalResults['X2'] - finalResults['X1']) / 2.0)
    cy = finalResults['Y2'] + (np.abs(finalResults['Y3'] - finalResults['Y2']) / 2.0)
    
    conditions = [
        (cx > 0.25 * imageWidth) & (cx < 0.75 * imageWidth) & 
        (cy > 0.25 * imageHeight) & (cy < 0.75 * imageHeight),
        (cx > 0.5 * imageWidth) & (cy > 0.5 * imageHeight),
        (cx > 0.5 * imageWidth),
        (cy > 0.5 * imageHeight)
    ]
    
    finalResults['ScreenLocation'] = np.select(conditions, ['A', 'D', 'C', 'E'], default='B')   
    
    return finalResults


def final_cleaning(finalResults, brandAsset_method):
    coord_cols = ['X1', 'Y1', 'X2', 'Y2', 'X3', 'Y3', 'X4', 'Y4']
    finalResults[coord_cols] = finalResults[coord_cols].fillna(0).astype(int)
    
    mapping_df = brandAsset_method[['Brand', 'Asset', 'Final_brand', 'Final_asset']].drop_duplicates()
    finalResults = finalResults.merge(mapping_df, on=['Brand', 'Asset'], how='left')
    finalResults['Asset'] = finalResults['Final_asset'].fillna(finalResults['Asset'])
    finalResults['Brand'] = finalResults['Final_brand'].fillna(finalResults['Brand'])
    finalResults = finalResults.drop(columns=['Final_asset', 'Final_brand'])
    
    return finalResults