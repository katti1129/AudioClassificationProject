using UnityEngine;

public class CameraSwitcher : MonoBehaviour
{
    public Camera mainCamera;   // メインカメラ
    public Camera fpvCamera;    // 歩行者視点カメラ

    private AudioListener mainListener;
    private AudioListener fpvListener;

    private bool isFPV = false;

    void Start()
    {
        // AudioListener を取得
        mainListener = mainCamera.GetComponent<AudioListener>();
        fpvListener  = fpvCamera.GetComponent<AudioListener>();

        // 初期状態
        mainCamera.gameObject.SetActive(true);
        fpvCamera.gameObject.SetActive(false);

        mainListener.enabled = true;
        fpvListener.enabled = false;
    }

    void Update()
    {
        if (Input.GetKeyDown(KeyCode.C))  // Cキーで切り替え
        {
            isFPV = !isFPV;

            // カメラの ON/OFF
            mainCamera.gameObject.SetActive(!isFPV);
            fpvCamera.gameObject.SetActive(isFPV);

            // AudioListener の ON/OFF（重要）
            mainListener.enabled = !isFPV;
            fpvListener.enabled  = isFPV;
        }
    }
}
