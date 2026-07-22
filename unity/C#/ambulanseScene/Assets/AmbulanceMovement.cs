using UnityEngine;

public class AmbulanceMovement : MonoBehaviour
{
    public float speed = 15f;
    public Vector3 startPos = new Vector3(0, 0.5f, -60f);
    public Vector3 endPos   = new Vector3(0, 0.5f, 60f);

    private Vector3 dir;

    void Start()
    {
        transform.position = startPos;
        dir = (endPos - startPos).normalized;
    }

    void Update()
    {
        transform.position += dir * speed * Time.deltaTime;

        if (Vector3.Distance(transform.position, endPos) < 1f)
        {
            transform.position = startPos;
        }
    }
}
