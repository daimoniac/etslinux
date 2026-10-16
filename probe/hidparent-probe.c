/*
 * Replicates the enumeration pattern that KNX ETS / Knx.Falcon.UsbAccessWindows
 * uses to find its USB licensing dongle, so the Wine HID/PnP layer can be
 * verified independently of ETS itself:
 *
 *   1. SetupDiGetClassDevs(GUID_DEVINTERFACE_HID)
 *   2. SetupDiEnumDeviceInterfaces / SetupDiGetDeviceInterfaceDetail
 *   3. CM_Get_Parent on the HID devnode
 *   4. CM_Get_Device_ID on the parent, parse USB VID/PID
 *   5. CreateFile on the HID interface path
 *
 * This is the chain broken by the CM_Get_Parent stub in WineHQ bug 59604
 * (fixed in Wine 11.10).
 *
 * Build (32-bit PE, the way ETS itself is built):
 *   i686-w64-mingw32-gcc -O2 -o hidparent-probe.exe hidparent-probe.c -lsetupapi -lcfgmgr32
 */
#include <windows.h>
#include <setupapi.h>
#include <cfgmgr32.h>
#include <stdio.h>

static const GUID hid_guid =
    {0x4d1e55b2,0xf16f,0x11cf,{0x88,0xcb,0x00,0x11,0x11,0x00,0x00,0x30}};

int main(int argc, char **argv)
{
    unsigned int want_vid = 0x2a07, want_pid = 0x0102;
    if (argc >= 3) { sscanf(argv[1], "%x", &want_vid); sscanf(argv[2], "%x", &want_pid); }

    printf("Looking for USB parent VID_%04X&PID_%04X\n\n", want_vid, want_pid);

    HDEVINFO set = SetupDiGetClassDevsA(&hid_guid, NULL, NULL,
                                        DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
    if (set == INVALID_HANDLE_VALUE) {
        printf("FAIL: SetupDiGetClassDevs failed (%lu)\n", GetLastError());
        return 2;
    }

    SP_DEVICE_INTERFACE_DATA iface = { sizeof(iface) };
    int idx = 0, found = 0;

    while (SetupDiEnumDeviceInterfaces(set, NULL, &hid_guid, idx++, &iface)) {
        DWORD need = 0;
        SetupDiGetDeviceInterfaceDetailA(set, &iface, NULL, 0, &need, NULL);
        if (!need) continue;

        SP_DEVICE_INTERFACE_DETAIL_DATA_A *det = malloc(need);
        det->cbSize = sizeof(*det);
        SP_DEVINFO_DATA devinfo = { sizeof(devinfo) };

        if (!SetupDiGetDeviceInterfaceDetailA(set, &iface, det, need, NULL, &devinfo)) {
            printf("[%d] SetupDiGetDeviceInterfaceDetail failed (%lu)\n", idx-1, GetLastError());
            free(det);
            continue;
        }

        char child_id[MAX_DEVICE_ID_LEN] = "";
        CM_Get_Device_IDA(devinfo.DevInst, child_id, sizeof(child_id), 0);
        printf("[%d] HID  : %s\n", idx-1, child_id);

        /* --- step 3: the call that bug 59604 was about --- */
        DEVINST parent = 0;
        CONFIGRET cr = CM_Get_Parent(&parent, devinfo.DevInst, 0);
        if (cr != CR_SUCCESS) {
            printf("     parent: CM_Get_Parent FAILED (CR=%d)%s\n", cr,
                   cr == CR_NO_SUCH_DEVNODE ? "  <-- the 59604 stub signature" : "");
            free(det);
            continue;
        }

        char parent_id[MAX_DEVICE_ID_LEN] = "";
        cr = CM_Get_Device_IDA(parent, parent_id, sizeof(parent_id), 0);
        if (cr != CR_SUCCESS) {
            printf("     parent: CM_Get_Device_ID FAILED (CR=%d)\n", cr);
            free(det);
            continue;
        }
        printf("     parent: %s\n", parent_id);

        unsigned int vid = 0, pid = 0;
        const char *v = strstr(parent_id, "VID_");
        const char *p = strstr(parent_id, "PID_");
        if (v && p && sscanf(v + 4, "%4x", &vid) == 1 && sscanf(p + 4, "%4x", &pid) == 1) {
            printf("     parsed: VID=%04X PID=%04X\n", vid, pid);
            if (vid == want_vid && pid == want_pid) {
                found = 1;
                printf("     *** MATCH: this is the target dongle ***\n");

                /* --- step 5: can we actually open it? --- */
                HANDLE h = CreateFileA(det->DevicePath,
                                       GENERIC_READ | GENERIC_WRITE,
                                       FILE_SHARE_READ | FILE_SHARE_WRITE,
                                       NULL, OPEN_EXISTING, 0, NULL);
                if (h == INVALID_HANDLE_VALUE) {
                    printf("     OPEN   : FAILED (%lu) on %s\n", GetLastError(), det->DevicePath);
                } else {
                    printf("     OPEN   : OK (%s)\n", det->DevicePath);
                    CloseHandle(h);
                }
            }
        } else {
            printf("     parsed: no VID/PID in parent id\n");
        }
        free(det);
    }

    SetupDiDestroyDeviceInfoList(set);
    printf("\n%s\n", found ? "RESULT: dongle found via the full ETS enumeration chain"
                           : "RESULT: dongle NOT found");
    return found ? 0 : 1;
}
