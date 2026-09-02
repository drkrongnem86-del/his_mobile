"""Test với filter đầy đủ"""
import requests
import base64
import json
import urllib.parse

TOKEN = "e365259dd4997a1a7235ccb48511044f413b1b63cbd46e26222fa4c6a9ffe8a4"
CLIENT_IP = "172.16.200.101"
BASE_URL = "http://172.16.9.6:1408"

def encode_param(api_data, limit=200):
    common = {
        "Messages": [], "BugCodes": [], "MessageCodes": [],
        "Start": 0, "Limit": limit, "LanguageCode": "VI", "Now": 0, "HasException": False,
    }
    param_dict = {"CommonParam": common, "ApiData": api_data}
    param_json = json.dumps(param_dict, ensure_ascii=False)
    return base64.b64encode(param_json.encode('utf-8')).decode('ascii')

headers = {"Content-Type": "application/json", "TokenCode": TOKEN, "ApplicationCode": "HIS", "ClientIpAddress": CLIENT_IP}

# Test với đúng filter của mobile app
print("=== Test với FILTER ĐẦY ĐỦ của mobile app (room 36, stt 1, 2) ===")
api_data = {
    "SERVICE_REQ_STT_IDs": [1, 2],
    "NOT_IN_SERVICE_REQ_TYPE_IDs": [6, 16, 15, 14, 7],
    "TDL_PATIENT_TYPE_IDs": [206, 1, 210, 202, 262, 182, 162, 2, 45, 102, 204, 205, 203, 44, 122, 242, 222, 142, 143, 209, 208, 207, 42, 43],
    "KEYWORD__SERVICE_REQ_CODE__TREATMENT_CODE__PATIENT_NAME__PATIENT_CODE": "",
    "EXECUTE_ROOM_ID": 36,
    "INTRUCTION_DATE__EQUAL": 20260823000000,
    "HAS_EXECUTE": True,
    "IS_NOT_KSK_REQURIED_APPROVAL__OR__IS_KSK_APPROVE": True,
    "ORDER_FIELD": "INTRUCTION_DATE", "ORDER_DIRECTION": "DESC",
    "ORDER_FIELD1": "SERVICE_REQ_STT_ID", "ORDER_DIRECTION1": "ASC",
    "ORDER_FIELD2": "PRIORITY", "ORDER_DIRECTION2": "DESC",
    "ORDER_FIELD3": "NUM_ORDER", "ORDER_DIRECTION3": "ASC",
}
param = encode_param(api_data, 200)
url = f"{BASE_URL}/api/HisServiceReq/GetLView?param={urllib.parse.quote(param)}"
try:
    r = requests.get(url, headers=headers, timeout=60)
    if r.status_code == 200:
        data = json.loads(r.text)
        items = data.get("Data", [])
        print(f"Total: {len(items)} patients")
        for p in items:
            print(f"  {p.get('TDL_PATIENT_NAME')} (mã: {p.get('TDL_PATIENT_CODE')}, room: {p.get('EXECUTE_ROOM_ID')}, stt: {p.get('SERVICE_REQ_STT_ID')}, type: {p.get('SERVICE_REQ_TYPE_ID')}, service: {p.get('SERVICE_NAME')})")
except Exception as e:
    print(f"Error: {e}")

# Test không có NOT_IN_SERVICE_REQ_TYPE_IDs
print("\n=== Test KHÔNG có NOT_IN_SERVICE_REQ_TYPE_IDs (room 36, stt 1, 2) ===")
api_data2 = dict(api_data)
del api_data2["NOT_IN_SERVICE_REQ_TYPE_IDs"]
param = encode_param(api_data2, 200)
url = f"{BASE_URL}/api/HisServiceReq/GetLView?param={urllib.parse.quote(param)}"
try:
    r = requests.get(url, headers=headers, timeout=60)
    if r.status_code == 200:
        data = json.loads(r.text)
        items = data.get("Data", [])
        print(f"Total: {len(items)} patients")
        for p in items:
            print(f"  {p.get('TDL_PATIENT_NAME')} (mã: {p.get('TDL_PATIENT_CODE')}, type: {p.get('SERVICE_REQ_TYPE_ID')})")
except Exception as e:
    print(f"Error: {e}")
