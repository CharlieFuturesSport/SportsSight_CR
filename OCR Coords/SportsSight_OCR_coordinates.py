import pandas as pd
import numpy as np
from typing import List, Dict, Tuple, Optional
from collections import defaultdict
import sql_helper_LR as lr
import os

results_columns = [
    'ModelType', 'Guid_ID', 'Sport', 'Event', 'Filename', 'Brand', 'Asset',
    'X1', 'Y1', 'X2', 'Y2', 'X3', 'Y3', 'X4', 'Y4',
    'Probability', 'Iteration', 'AcceptedExposure', 'Original_Tag',
    'Original_BrandMessaging', 'Original_Asset', 'ScreenSize', 'ScreenLocation'
]

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



class TVGIDetector:
    """
    Detects potential TV Graphics Inserts (TVGIs) from OCR data based on:
    - Consistent screen locations
    - Similar sizes
    - Consecutive filename appearances
    - Similar orientations
    """
    
    def __init__(self, 
                 position_tolerance: float = 0.05,
                 size_tolerance: float = 0.15,
                 angle_tolerance: float = 5.0):
        """
        Initialize TVGI detector with tolerance parameters.
        
        Args:
            position_tolerance: Relative tolerance for position matching (0-1)
            size_tolerance: Relative tolerance for size matching (0-1)
            angle_tolerance: Degrees tolerance for angle matching
        """
        self.position_tolerance = position_tolerance
        self.size_tolerance = size_tolerance
        self.angle_tolerance = angle_tolerance
    
    def format_OCR(self,   ocrResults,
                           events: Optional[List[str]] = None,
                           brands: Optional[List[str]] = None,
                           cleaned_text_list: Optional[List[str]] = None) -> pd.DataFrame:

        df = ocrResults.copy()
        # Filter by SportsEvent if events list is provided
        if events:
            df = df[df['SportsEvent'].isin(events)]
        # Filter by Brand if brands list is provided
        if brands:
            brands_lower = [b.lower() for b in brands]
            #Standardise the brands regardless of lower/upper case
            df = df[df['Brand'].str.lower().isin(brands_lower)]
        # Filter by cleaned_text if cleaned_text_list is provided
        if cleaned_text_list:
            df = df[df['cleaned_text'].isin(cleaned_text_list)]

        return df
    
    def calculate_box_metrics(self, df: pd.DataFrame) -> pd.DataFrame:
        """Calculate normalized position, size, and center for each OCR box."""
        df = df.copy()
        
        # Calculate box center (normalized by image dimensions)
        df['center_x'] = ((df['BoxTopLeftX'] + df['BoxBottomRightX']) / 2) / df['imageWidth']
        df['center_y'] = ((df['BoxTopLeftY'] + df['BoxBottomRightY']) / 2) / df['imageHeight']
        
        # Calculate box dimensions (normalized)
        df['box_width'] = abs(df['BoxBottomRightX'] - df['BoxTopLeftX']) / df['imageWidth']
        df['box_height'] = abs(df['BoxBottomRightY'] - df['BoxTopLeftY']) / df['imageHeight']
        
        # Calculate box area
        df['box_area'] = df['box_width'] * df['box_height']
        
        return df
    
    def extract_frame_number(self, filename: str) -> int:
        """
        Extract frame number from filename.
        Format: 'BWSL_EVEvTH_GW2/012767.jpg' -> 12767
        """
        import re
        # Extract the numeric part before the file extension
        # This gets the filename after the last slash
        base_filename = filename.split('/')[-1]
        # Remove the extension and convert to int
        frame_str = base_filename.split('.')[0]
        try:
            return int(frame_str)
        except ValueError:
            # Fallback: try to find any digits in the filename
            matches = re.findall(r'(\d+)', base_filename)
            if matches:
                return int(matches[-1])
            return 0
    
    def is_similar(self, row1, row2) -> bool:
        """Combined check for position, size, angle and brand consistency."""
        # Brand
        # If the brands are different, they are NOT similar, regardless of where they are on the screen.
        if row1.get('Brand') != row2.get('Brand'):
            return False
               
        # Position
        dx = abs(row1['center_x'] - row2['center_x'])
        dy = abs(row1['center_y'] - row2['center_y'])
        if dx > self.position_tolerance or dy > self.position_tolerance:
            return False
        
        # Size
        w1, w2 = row1['box_width'], row2['box_width']
        h1, h2 = row1['box_height'], row2['box_height']
        width_ratio = max(w1, w2) / (min(w1, w2) + 1e-10)
        height_ratio = max(h1, h2) / (min(h1, h2) + 1e-10)
        if width_ratio > (1 + self.size_tolerance) or height_ratio > (1 + self.size_tolerance):
            return False
        
        # Angle
        a1, a2 = row1.get('Angle'), row2.get('Angle')
        if not (pd.isna(a1) or pd.isna(a2)):
            if abs(a1 - a2) > self.angle_tolerance:
                return False
                
        return True

    def detect_tvgi_clusters(self, df: pd.DataFrame, group_events: bool = False) -> List[Dict]:
        df = self.calculate_box_metrics(df)
        df['frame_number'] = df['Filename'].apply(self.extract_frame_number)
        
        raw_summaries = []
        
        if group_events:
            rows = df.to_dict('records')
            clusters = self._cluster_rows(rows)
            for c in clusters:
                raw_summaries.append(self._create_cluster_summary(c, is_grouped=True))
            
        else:
            # OPTION B: Keep events separate (Current Behavior)
            for event in df['SportsEvent'].unique():
                event_df = df[df['SportsEvent'] == event].copy()
                rows = event_df.to_dict('records')
                clusters = self._cluster_rows(rows)
                for c in clusters:
                    raw_summaries.append(self._create_cluster_summary(c, is_grouped=False))
        
        return self._merge_similar_summaries(raw_summaries)
        # return raw_summaries

    def _cluster_rows(self, rows: List[Dict]) -> List[List[Dict]]:
        """Internal helper to handle the actual similarity looping."""
        clusters = []
        for row in rows:
            matched = False
            for cluster in clusters:
                if self.is_similar(row, cluster[0]):
                    cluster.append(row)
                    matched = True
                    break
            if not matched:
                clusters.append([row])
        return clusters

    def _merge_similar_summaries(self, summaries: List[Dict]) -> List[Dict]:
        if not summaries: return []
        merged = []
        used = set()
        summaries = sorted(summaries, key=lambda x: x['total_frames'], reverse=True)

        for i, s1 in enumerate(summaries):
            if i in used: continue
            current_group = [s1]
            used.add(i)
            
            for j, s2 in enumerate(summaries):
                if j <= i or j in used: continue
                # Check distance apart
                dist = np.sqrt((s1['avg_center_x'] - s2['avg_center_x'])**2 + 
                               (s1['avg_center_y'] - s2['avg_center_y'])**2)
                # Also check if widths and heights are similar
                width_diff = abs(s1['avg_width'] - s2['avg_width'])
                height_diff = abs(s1['avg_height'] - s2['avg_height'])
                
                if dist < 0.01 and width_diff < 0.01 and height_diff < 0.01:
                    current_group.append(s2)
                    used.add(j)
            
            if len(current_group) > 1:
                merged.append(self._combine_summaries(current_group))
            else:
                merged.append(s1)
        return merged

    def _combine_summaries(self, group: List[Dict]) -> Dict:
        combined = group[0].copy()
        all_files = []
        all_ids = []
        all_brands = set()
        for g in group:
            all_files.extend(g['filenames'])
            all_ids.extend(g['record_ids'])
            all_brands.update(g['brands'])
        
        combined['filenames'] = sorted(list(set(all_files)))
        combined['record_ids'] = sorted(list(set(all_ids))) # Deduplicate SQL IDs
        combined['total_frames'] = len(combined['filenames'])
        combined['brands'] = sorted(list(all_brands))
        return combined

    def _create_cluster_summary(self, cluster: List[Dict], is_grouped: bool = False) -> Dict:
        cdf = pd.DataFrame(cluster)
        
        # Determine the name logic
        if is_grouped:
            event_label = "MULTIPLE_EVENTS"
            unique_events = cdf['SportsEvent'].unique().tolist()
        else:
            event_label = cdf.iloc[0]['SportsEvent']
            unique_events = [event_label]
        
        
        return {
            'cluster_id': f"TVGI_{cdf.iloc[0]['SportsEvent']}_{cdf.iloc[0]['ID']}",
            'event': ", ".join(unique_events) if is_grouped else event_label,            
            'total_frames': len(cdf['Filename'].unique()),
            'frame_range': (int(cdf['frame_number'].min()), int(cdf['frame_number'].max())),
            'filenames': sorted(cdf['Filename'].unique().tolist()),
            'record_ids': sorted(cdf['ID'].unique().tolist()), # Track IDs here
            'avg_center_x': cdf['center_x'].mean(),
            'avg_center_y': cdf['center_y'].mean(),
            'avg_width': cdf['box_width'].mean(),
            'avg_height': cdf['box_height'].mean(),
            'avg_angle': cdf['Angle'].mean() if 'Angle' in cdf else 0,
            'brands': cdf['Brand'].dropna().unique().tolist(),
            'sample_text': cdf['cleaned_text'].iloc[0] if 'cleaned_text' in cdf else ""
        }
    
    def format_for_excel(self, report_df: pd.DataFrame) -> pd.DataFrame:
        """Truncates long lists specifically for Excel readability."""
        out = report_df.copy()
        for col in ['filenames', 'record_ids']:
            out[
col] = out[col].apply(lambda x: f"{x[:10]}...[{len(x)-20} more]...{x[-10:]}" if len(x) > 20 else x)
        return out
   
        

def ocr_coords_toSQL_proc(ocrResults, events, output_path, iteration
                    ,group_events=False,brands=None,cleaned_text_list=None
                    ,position_tolerance=0.05
                    ,size_tolerance=0.05
                    ,angle_tolerance=2.0
                    ,min_frames=10):
    
    detector = TVGIDetector(
        position_tolerance=position_tolerance,
        size_tolerance=size_tolerance,
        angle_tolerance=angle_tolerance
    )
    
    df = detector.format_OCR(
        ocrResults,
        events,
        brands,
        cleaned_text_list
    )
    
    clusters = detector.detect_tvgi_clusters(df, group_events)
    report = pd.DataFrame(clusters)
    report = report[report['total_frames'] >= min_frames]
    report = report.sort_values(by='total_frames', ascending=False)
    
    # Save for User Input
    with pd.ExcelWriter(output_path, engine='openpyxl') as writer:
        detector.format_for_excel(report).to_excel(writer, sheet_name='TVGI_report', index=False)
        pd.DataFrame(columns=['cluster_id','Brand','Asset']).to_excel(writer, sheet_name='Accepted_clusters', index=False)
    
    print(f"Report saved. Please update 'Accepted_clusters' tab in: {output_path}")

    # Handle User Input
    if input("Have you saved the accepted results? (Y/N): ").upper() == 'Y':
        accepted_input = pd.read_excel(output_path, sheet_name='Accepted_clusters')
        
        if not accepted_input.empty:       
            # Join user choices back to the 'report' variable to get info about the location of the coordinates
            merged = pd.merge(accepted_input[['cluster_id', 'Brand', 'Asset']], 
                              report[['cluster_id', 'avg_center_x','avg_center_y','avg_width','avg_height','avg_angle','brands','sample_text']], on='cluster_id')
            
            # Populate new table in SQL
            ref_table = merged.copy()
            ref_table = ref_table.drop('brands', axis=1)
    
    return ref_table
            

def calculate_box_metrics(df):
    """Calculate normalized position, size, and center for each OCR box."""
    df = df.copy()
    
    # Calculate box center (normalized by image dimensions)
    df['center_x'] = ((df['BoxTopLeftX'] + df['BoxBottomRightX']) / 2) / df['imageWidth']
    df['center_y'] = ((df['BoxTopLeftY'] + df['BoxBottomRightY']) / 2) / df['imageHeight']
    
    # Calculate box dimensions (normalized)
    df['box_width'] = abs(df['BoxBottomRightX'] - df['BoxTopLeftX']) / df['imageWidth']
    df['box_height'] = abs(df['BoxBottomRightY'] - df['BoxTopLeftY']) / df['imageHeight']
    
    # Calculate box area
    df['box_area'] = df['box_width'] * df['box_height']
    
    return df

def apply_confirmed_coords(large_df, ref_df, position_tolerance, size_tolerance, angle_tolerance):
    """
    Applies the reference zones to a massive dataset.
    """
    # Calculate metrics for the 1M+ rows
    large_df = calculate_box_metrics(large_df)
    final_matches = []

    # Iterate through our small reference zones
    for idx, zone in ref_df.iterrows():
        # 1. Position & Size Masks
        mask = (
            (abs(large_df['center_x'] - zone['avg_center_x']) <= position_tolerance) &
            (abs(large_df['center_y'] - zone['avg_center_y']) <= position_tolerance) &
            (large_df['box_width'] / zone['avg_width']).between(1 - size_tolerance, 1 + size_tolerance) &
            (large_df['box_height'] / zone['avg_height']).between(1 - size_tolerance, 1 + size_tolerance)
            # (abs(large_df['box_width'] - zone['avg_width']) <= size_tolerance) & 
            # (abs(large_df['box_height'] - zone['avg_height']) <= size_tolerance)
        )
        
        # 2. Angle Mask (Handling potential NaNs)
        if 'Angle' in large_df.columns and 'avg_angle' in zone:
            angle_data = large_df['Angle'].fillna(0)
            angle_ref = zone['avg_angle']
            angle_diff = abs(angle_data - angle_ref)
            # Optional: Handle wrap-around for angles (e.g. 359 to 1)
            # angle_diff = np.minimum(angle_diff, 360 - angle_diff) 
            mask = mask & (angle_diff <= angle_tolerance)

        matched_rows = large_df[mask].copy()
        
        if not matched_rows.empty:
            # Pull the final naming convention from the ref_df row
            matched_rows['Brand'] = zone['Brand']
            matched_rows['Asset'] = zone['Asset']
            matched_rows['Reference_Cluster_ID'] = zone['cluster_id']
            final_matches.append(matched_rows)
            
    if not final_matches:
        return pd.DataFrame()

    result = pd.concat(final_matches)
    
    print(f"Total matches found before deduplication: {len(result)}")
    
    return result

            
def apply_SQL_coords(ocrResults,sql_coords,iteration, position_tolerance=0.05,size_tolerance=0.05,angle_tolerance=2.0):
    
    modelType = 'OCR_Coords'
    final_df = apply_confirmed_coords(ocrResults, sql_coords,position_tolerance,size_tolerance,angle_tolerance)
    
    if not final_df.empty:
        # Format for CombinedResults
        final_df['ModelType'] = modelType 
        final_df['Guid_ID'] = final_df['OcrLineID']
        final_df = final_df.rename(columns={'SportsEvent': 'Event'})
        final_df['Event'] = final_df['Event'].str[:-1]
        final_df['Filename'] = final_df['Filename'].str[-10:] 
        final_df = final_df.rename(columns={'original_text': 'Original_BrandMessaging'})
        final_df = final_df.rename(columns=column_mapping)
        final_df['Probability'] = 1
        final_df['Iteration'] = iteration
        final_df['AcceptedExposure'] = 1
        # Calculate screensize
        box_area = (final_df['X2'] - final_df['X1']).abs() * (final_df['Y4'] - final_df['Y1']).abs()
        screen_area = final_df['imageWidth'] * final_df['imageHeight']   
        final_df['ScreenSize'] = (box_area / screen_area)
    
        # final_output = final_df.reindex(columns=results_columns)
        
        existing_cols = [c for c in results_columns if c in final_df.columns]
        final_output = final_df[existing_cols].copy()
        
        
    else:
        print("Zero matches found. Check if your position_tolerance needs to be higher.")
        # Create an empty dataframe with your required columns to prevent downstream crashes
        final_output = pd.DataFrame()
        
    return final_output

