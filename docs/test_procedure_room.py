"""Test HIS Pro GetLView API với token hiện tại"""
import requests
import base64
import json
import urllib.parse

# Token mới nhất (từ v3.0.166 hardcode)
TOKEN = "e365259dd4997a1a7235ccb48511044f413b1b63cbd46e26222fa4c6a9ffe8a4"
CLIENT_IP = "172.16.200.101"
BASE_URL = "http://172.16.9.6:1408"

def encode_param(api_data, limit=200):
    common = {
        "Messages": [],
        "BugCodes": [],
        "MessageCodes": [],
        "Start": 0,
        "Limit": limit,
        "LanguageCode": "VI",
        "Now": 0,
        "HasException": False,
    }
    param_dict = {"CommonParam": common, "ApiData": api_data}
    param_json = json.dumps(param_dict, ensure_ascii=False)
    return base64.b64encode(param_json.encode('utf-8')).decode('ascii')

# Test 1: GetLView room 36 với filter giống mobile app
api_data_room36 = {
    "SERVICE_REQ_STT_IDs": [1, 2, 3],
    "NOT_IN_SERVICE_REQ_TYPE_IDs": [6, 16, 15, 14, 7],
    "TDL_PATIENT_TYPE_IDs": [206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203, 44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43],
    "KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE": "",
    "EXECUTE_ROOM_ID": 36,
    "INTRUCTION_DATE__EQUAL": 20260823000000,
    "HAS_EXECUTE": True,
    "IS_NOT_KSK_REQURIED_APPROVAL__OR__IS_KSK_APPROVE": True,
    "ORDER_FIELD": "INTRUCTION_DATE",
    "ORDER_DIRECTION": "DESC",
    "ORDER_FIELD1": "SERVICE_REQ_STT_ID",
    "ORDER_DIRECTION1": "ASC",
    "ORDER_FIELD2": "PRIORITY",
    "ORDER_DIRECTION2": "DESC",
    "ORDER_FIELD3": "NUM_ORDER",
    "ORDER_DIRECTION3": "ASC",
}

param = encode_param(api_data_room36, 200)
url = f"{BASE_URL}/api/HisServiceReq/GetLView?param={urllib.parse.quote(param)}"

headers = {
    "Content-Type": "application/json",
    "TokenCode": TOKEN,
    "ApplicationCode": "HIS",
    "ClientIpAddress": CLIENT_IP,
}

print(f"=== Test 1: HIS Pro GetLView room 36 (Phòng tủ thuật HSCC) ===")
print(f"URL: {url[:200]}")
print(f"Token: {TOKEN[:16]}...")
try:
    r = requests.get(url, headers=headers, timeout=30)
    print(f"Status: {r.status_code}")
    if r.status_code == 200:
        data = json.loads(r.text)
        items = data.get("Data", [])
        print(f"Total patients: {len(items)}")
        if items:
            print(f"\nFirst patient fields: {list(items[0].keys())[:20]}")
            print(f"\nFirst patient (raw):")
            for k, v in items[0].items():
                if 'name' in k.lower() or 'patient' in k.lower() or 'tdl_' in k.lower():
                    print(f"  {k} = {v}")
        # Save full response
        with open(r'C:\Users\drkro\Desktop\procroom_response.json', 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        print(f"\nSaved to procroom_response.json")
    else:
        print(f"Response: {r.text[:500]}")
except Exception as e:
    print(f"Error: {e}")

# Test 2: Same but with filter "Chưa kết thúc" (status 1, 2) only
api_data_chua_kt = dict(api_data_room36)
api_data_chua_kt["SERVICE_REQ_STT_IDs"] = [1, 2]
param2 = encode_param(api_data_chua_kt, 200)
url2 = f"{BASE_URL}/api/HisServiceReq/GetLView?param={urllib.parse.quote(param2)}"

print(f"\n=== Test 2: GetLView room 36 chỉ status 1, 2 (Chưa kết thúc) ===")
try:
    r = requests.get(url2, headers=headers, timeout=30)
    print(f"Status: {r.status_code}")
    if r.status_code == 200:
        data = json.loads(r.text)
        items = data.get("Data", [])
        print(f"Total patients: {len(items)}")
        if items:
            for i, p in enumerate(items[:5]):
                name = p.get('TDL_PATIENT_NAME', 'N/A')
                code = p.get('TDL_PATIENT_CODE', 'N/A')
                stt = p.get('SERVICE_REQ_STT_ID', 'N/A')
                print(f"  {i+1}. {name} (mã: {code}, stt: {stt})")
except Exception as e:
    print(f"Error: {e}")

# Test 3: Data 3000 API for comparison
print(f"\n=== Test 3: Data 3000 benh-nhan-buong-benh room 36 ===")
data3000_url = "http://113.163.187.3:3000/v1/patient/benh-nhan-buong-benh"
try:
    r = requests.post(data3000_url, json={
        "USERNAME": "nemk",
        "BED_ROOM_IDs": [36],
    }, timeout=30)
    print(f"Status: {r.status_code}")
    if r.status_code == 200:
        data = r.json()
        items = data if isinstance(data, list) else data.get("data", [])
        print(f"Total patients: {len(items)}")
        if items:
            for i, p in enumerate(items[:5]):
                # Try different field names
                name = p.get('HOTENBN') or p.get('hotenbn') or p.get('TDL_PATIENT_NAME') or p.get('patientName') or 'N/A'
                print(f"  {i+1}. {name} - fields: {list(p.keys())[:10]}")
            # Save
            with open(r'C:\Users\drkro\Desktop\data3000_room36.json', 'w', encoding='utf-8') as f:
                json.dump(data, f, ensure_ascii=False, indent=2)
            print(f"\nSaved to data3000_room36.json")
except Exception as e:
    print(f"Error: {e}")
