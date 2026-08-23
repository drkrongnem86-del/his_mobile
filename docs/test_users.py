"""Test HIS Pro users APIs"""
import requests
import base64
import json
import urllib.parse

TOKEN = "e365259dd4997a1a7235ccb48511044f413b1b63cbd46e26222fa4c6a9ffe8a4"
CLIENT_IP = "172.16.200.101"

def encode_param(api_data, limit=200):
    common = {
        "Messages": [], "BugCodes": [], "MessageCodes": [],
        "Start": 0, "Limit": limit, "LanguageCode": "VI", "Now": 0, "HasException": False,
    }
    param_dict = {"CommonParam": common, "ApiData": api_data}
    param_json = json.dumps(param_dict, ensure_ascii=False)
    return base64.b64encode(param_json.encode('utf-8')).decode('ascii')

headers = {"Content-Type": "application/json", "TokenCode": TOKEN, "ApplicationCode": "HIS", "ClientIpAddress": CLIENT_IP}

# Test 1: HisExecuteUser/GetView - OCR port 1425
print("=== Test 1: HisExecuteUser/GetView port 1425 (HIS Pro OCR/MCH) ===")
for url_base in ["http://172.16.9.6:1425", "http://172.16.9.6:1408"]:
    api_data = {
        "IS_ACTIVE": 1,
        "DEPARTMENT_ID": 22,  # HSCC
        "ORDER_FIELD": "LOGINNAME", "ORDER_DIRECTION": "ASC",
    }
    param = encode_param(api_data, 50)
    url = f"{url_base}/api/HisExecuteUser/GetView?param={urllib.parse.quote(param)}"
    try:
        r = requests.get(url, headers=headers, timeout=20)
        if r.status_code == 200:
            data = json.loads(r.text)
            items = data.get("Data", [])
            print(f"\n{url_base}: {len(items)} users")
            if items:
                # Check fields
                print(f"Fields: {list(items[0].keys())[:20]}")
                # Find ĐỖ Văn Dũng or similar
                for u in items[:5]:
                    name = u.get('USERNAME') or u.get('username') or u.get('FULL_NAME') or 'N/A'
                    login = u.get('LOGINNAME') or u.get('loginname') or 'N/A'
                    print(f"  - {login} - {name} (dept: {u.get('DEPARTMENT_ID')}, role: {u.get('EXECUTE_ROLE_ID')})")
                # Find Doan Thi Kim An's executor
                doan = [u for u in items if 'DŨNG' in str(u.get('USERNAME', '')).upper() or 'DUNG' in str(u.get('USERNAME', '')).upper() or 'DO' in str(u.get('LOGINNAME', '')).upper()]
                if doan:
                    print(f"\n  Matching DŨNG:")
                    for u in doan:
                        print(f"    {u.get('LOGINNAME')} - {u.get('USERNAME')}")
        else:
            print(f"{url_base}: HTTP {r.status_code}")
    except Exception as e:
        print(f"{url_base}: Error {str(e)[:80]}")

# Test 2: HisEmployee/Get - ACS 1401
print("\n=== Test 2: HisEmployee/Get port 1401 ===")
api_data = {
    "IS_ACTIVE": 1,
    "DEPARTMENT_ID": 22,
    "ORDER_FIELD": "LOGINNAME", "ORDER_DIRECTION": "ASC",
}
param = encode_param(api_data, 50)
url = f"http://172.16.9.6:1401/api/HisEmployee/Get?param={urllib.parse.quote(param)}"
try:
    r = requests.get(url, headers=headers, timeout=20)
    if r.status_code == 200:
        data = json.loads(r.text)
        items = data.get("Data", [])
        print(f"HisEmployee: {len(items)} users")
        if items:
            print(f"Fields: {list(items[0].keys())[:20]}")
            for u in items[:5]:
                print(f"  - {u.get('LOGINNAME') or u.get('loginname')} - {u.get('USERNAME') or u.get('username') or u.get('FULL_NAME')}")
except Exception as e:
    print(f"Error: {e}")

# Test 3: HisUser/Get - ACS 1401
print("\n=== Test 3: HisUser/Get port 1401 ===")
api_data = {
    "IS_ACTIVE": 1,
    "ORDER_FIELD": "LOGINNAME", "ORDER_DIRECTION": "ASC",
}
param = encode_param(api_data, 50)
url = f"http://172.16.9.6:1401/api/HisUser/Get?param={urllib.parse.quote(param)}"
try:
    r = requests.get(url, headers=headers, timeout=20)
    if r.status_code == 200:
        data = json.loads(r.text)
        items = data.get("Data", [])
        print(f"HisUser: {len(items)} users")
        if items:
            print(f"Fields: {list(items[0].keys())[:20]}")
            for u in items[:5]:
                print(f"  - {u.get('LOGINNAME') or u.get('loginname')} - {u.get('USERNAME') or u.get('username')}")
except Exception as e:
    print(f"Error: {e}")

# Test 4: AcsUser/Get - 1401
print("\n=== Test 4: AcsUser/Get port 1401 ===")
param = encode_param({"IS_ACTIVE": 1, "LIMIT": 50}, 50)
url = f"http://172.16.9.6:1401/api/AcsUser/Get?param={urllib.parse.quote(param)}"
try:
    r = requests.get(url, headers=headers, timeout=20)
    if r.status_code == 200:
        data = json.loads(r.text)
        items = data.get("Data", [])
        print(f"AcsUser: {len(items)} users")
        if items:
            print(f"Fields: {list(items[0].keys())[:20]}")
            for u in items[:5]:
                print(f"  - {u.get('LOGINNAME') or u.get('loginname')} - {u.get('USERNAME') or u.get('username')}")
except Exception as e:
    print(f"Error: {e}")
