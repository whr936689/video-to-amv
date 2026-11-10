package com.example.amvconverter;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ClipData;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.database.Cursor;
import android.media.MediaMetadataRetriever;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.provider.OpenableColumns;
import android.text.method.ScrollingMovementMethod;
import android.view.Gravity;
import android.view.View;
import android.widget.ArrayAdapter;
import android.widget.Button;
import android.widget.CheckBox;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.RadioGroup;
import android.widget.Spinner;
import android.widget.TextView;
import android.widget.Toast;

import android.view.LayoutInflater;
import android.view.View;
import android.view.ViewGroup;
import android.widget.BaseAdapter;
import android.widget.CompoundButton;

import com.github.hiteshsondhi88.libffmpeg.ExecuteBinaryResponseHandler;
import com.github.hiteshsondhi88.libffmpeg.FFmpeg;
import com.github.hiteshsondhi88.libffmpeg.FFmpegLoadBinaryResponseHandler;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.List;

public class MainActivity extends Activity {

    private static final int REQ_VIDEO = 1001;
    private static final int REQ_AUDIO = 1002;
    private static final int REQ_PERM = 1003;
    private static final int REQ_BATCH_ADD = 1004;
    private static final int REQ_BATCH_AUDIO = 1005;
    private static final int REQ_PERM_LAUNCH = 1006;

    private static final String[] AMV_SIZES = {
            "160×128", "176×128", "176×144", "192×160", "208×120", "208×160",
            "208×176", "320×240"};
    private static final int[][] AMV_DIMS = {
            {160, 128}, {176, 128}, {176, 144}, {192, 160}, {208, 120}, {208, 160},
            {208, 176}, {320, 240}};

    private static final String[] AVI_SIZES = {
            "160×128", "176×128", "176×144", "192×160", "208×120", "208×160",
            "208×176", "320×240"};
    private static final int[][] AVI_DIMS = {
            {160, 128}, {176, 128}, {176, 144}, {192, 160}, {208, 120}, {208, 160},
            {208, 176}, {320, 240}};

    private static final String[] TRANSFORMS = {
            "正常", "上下交换", "左右交换", "上下-左右交换", "顺时针旋转90度", "逆时针旋转90度"};
    private static final String[] TRANSFORM_FILTERS = {
            "", "vflip", "hflip", "vflip,hflip", "transpose=1", "transpose=2"};

    private static final String[] QUALITIES = {"high", "middle", "low"};
    private static final int[] QUALITY_Q = {3, 6, 10};

    private static final String[] FPS_LABELS = {"10 fps", "15 fps", "25 fps"};
    private static final int[] FPS_VALUES = {10, 15, 25};

    private static final String[] BITRATES = {"64K", "88K", "128K", "192K"};

    private Button btnPick;
    private Button btnPickAudio;
    private Button btnConvert;
    private Button btnAbout;
    private TextView tvVideoInfo;
    private TextView tvAudioName;
    private TextView tvStatus;
    private TextView tvLog;
    private RadioGroup rgFormat;
    private Spinner spSize;
    private Spinner spFps;
    private Spinner spTransform;
    private Spinner spQuality;
    private Spinner spBitrate;
    private CheckBox cbVideoSync;
    private CheckBox cbAudioSync;
    private CheckBox cbCut;
    private CheckBox cbAutoPlay;
    private LinearLayout layoutCut;
    private EditText etStart;
    private EditText etEnd;
    private ProgressBar progress;

    // 输出目录
    private TextView tvOutputDir;
    private Button btnPickOutput;
    private Button btnResetOutput;
    private SharedPreferences prefs;
    private String outputDirOverride;

    // 批量处理相关
    private ListView lvBatch;
    private Button btnBatchAdd;
    private Button btnBatchRemove;
    private Button btnBatchClear;
    private Button btnBatchConvert;
    private ProgressBar progressBatch;
    private TextView tvBatchStatus;
    private final List<BatchItem> batchItems = new ArrayList<BatchItem>();
    private BatchAdapter batchAdapter;
    private int batchAudioForIndex = -1;
    private boolean batchRunning;
    private boolean permRequestedForBatch;
    private BatchItem currentBatchItem;

    private FFmpeg ffmpeg;
    private boolean ffmpegReady;
    private boolean running;

    private String videoPath;
    private String videoName;
    private String audioPath;
    private String audioName;
    private int durationSec;
    private boolean hasAudio = true;
    private double totalSec;

    private final StringBuilder logBuffer = new StringBuilder();

    private static class BatchItem {
        String videoPath;
        String videoName;
        String audioPath;
        String audioName;
        int durationSec;
        boolean hasAudio = true;
        boolean checked = true;
        int status = 0; // 0 未处理 1 转换中 2 已完成 3 失败
        int progress = 0; // 0-100
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        btnPick = findViewById(R.id.btnPick);
        btnPickAudio = findViewById(R.id.btnPickAudio);
        btnConvert = findViewById(R.id.btnConvert);
        btnAbout = findViewById(R.id.btnAbout);
        tvVideoInfo = findViewById(R.id.tvVideoInfo);
        tvAudioName = findViewById(R.id.tvAudioName);
        tvStatus = findViewById(R.id.tvStatus);
        tvLog = findViewById(R.id.tvLog);
        rgFormat = findViewById(R.id.rgFormat);
        spSize = findViewById(R.id.spSize);
        spFps = findViewById(R.id.spFps);
        spTransform = findViewById(R.id.spTransform);
        spQuality = findViewById(R.id.spQuality);
        spBitrate = findViewById(R.id.spBitrate);
        cbVideoSync = findViewById(R.id.cbVideoSync);
        cbAudioSync = findViewById(R.id.cbAudioSync);
        cbCut = findViewById(R.id.cbCut);
        cbAutoPlay = findViewById(R.id.cbAutoPlay);
        layoutCut = findViewById(R.id.layoutCut);
        etStart = findViewById(R.id.etStart);
        etEnd = findViewById(R.id.etEnd);
        progress = findViewById(R.id.progress);

        tvOutputDir = findViewById(R.id.tvOutputDir);
        btnPickOutput = findViewById(R.id.btnPickOutput);
        btnResetOutput = findViewById(R.id.btnResetOutput);
        prefs = getSharedPreferences("amv", MODE_PRIVATE);
        outputDirOverride = prefs.getString("output_dir", null);
        invalidateOldFfmpegBinary();
        updateOutputDirLabel();

        lvBatch = findViewById(R.id.lvBatch);
        btnBatchAdd = findViewById(R.id.btnBatchAdd);
        btnBatchRemove = findViewById(R.id.btnBatchRemove);
        btnBatchClear = findViewById(R.id.btnBatchClear);
        btnBatchConvert = findViewById(R.id.btnBatchConvert);
        progressBatch = findViewById(R.id.progressBatch);
        tvBatchStatus = findViewById(R.id.tvBatchStatus);
        batchAdapter = new BatchAdapter();
        lvBatch.setAdapter(batchAdapter);

        tvLog.setMovementMethod(new ScrollingMovementMethod());

        setSpinner(spSize, AMV_SIZES);
        setSpinner(spFps, FPS_LABELS);
        setSpinner(spTransform, TRANSFORMS);
        setSpinner(spQuality, QUALITIES);
        setSpinner(spBitrate, BITRATES);
        spFps.setSelection(1);
        spQuality.setSelection(1);
        spBitrate.setSelection(1);
        spBitrate.setEnabled(false);

        rgFormat.setOnCheckedChangeListener(new RadioGroup.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(RadioGroup group, int checkedId) {
                boolean avi = checkedId == R.id.rbAvi;
                setSpinner(spSize, avi ? AVI_SIZES : AMV_SIZES);
                spBitrate.setEnabled(!avi);
            }
        });

        cbCut.setOnCheckedChangeListener(new android.widget.CompoundButton.OnCheckedChangeListener() {
            @Override
            public void onCheckedChanged(android.widget.CompoundButton buttonView, boolean isChecked) {
                layoutCut.setVisibility(isChecked ? View.VISIBLE : View.GONE);
            }
        });

        btnAbout.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showAbout();
            }
        });

        btnPick.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                intent.setType("video/*");
                startActivityForResult(Intent.createChooser(intent, "选择视频"), REQ_VIDEO);
            }
        });

        btnPickAudio.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                intent.setType("audio/*");
                startActivityForResult(Intent.createChooser(intent, "选择音频"), REQ_AUDIO);
            }
        });

        btnConvert.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startConvert();
            }
        });

        btnBatchAdd.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
                intent.setType("video/*");
                intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                startActivityForResult(Intent.createChooser(intent, "选择视频（可多选）"), REQ_BATCH_ADD);
            }
        });

        btnBatchRemove.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                for (int i = batchItems.size() - 1; i >= 0; i--) {
                    if (batchItems.get(i).checked) {
                        batchItems.remove(i);
                    }
                }
                batchAdapter.notifyDataSetChanged();
                updateBatchStatus();
            }
        });

        btnBatchClear.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                batchItems.clear();
                batchAdapter.notifyDataSetChanged();
                updateBatchStatus();
            }
        });

        btnBatchConvert.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startBatchConvert();
            }
        });

        btnPickOutput.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                showPickOutputDir();
            }
        });

        btnResetOutput.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                outputDirOverride = null;
                prefs.edit().remove("output_dir").apply();
                updateOutputDirLabel();
                toast("已恢复默认输出目录");
            }
        });

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !hasStoragePermission()) {
            new AlertDialog.Builder(this)
                    .setTitle("需要存储权限")
                    .setMessage("视频转 AMV 需要存储权限，才能把转换结果保存到 Movies/AMV 或你选择的目录。")
                    .setPositiveButton("去授权", new android.content.DialogInterface.OnClickListener() {
                        @Override
                        public void onClick(android.content.DialogInterface dialog, int which) {
                            requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE},
                                    REQ_PERM_LAUNCH);
                        }
                    })
                    .setNegativeButton("稍后", null)
                    .show();
        }

        ffmpeg = FFmpeg.getInstance(this);
        try {
            ffmpeg.loadBinary(new FFmpegLoadBinaryResponseHandler() {
                @Override
                public void onFailure() {
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            appendLog("FFmpeg 加载失败");
                            toast("FFmpeg 加载失败，无法转换");
                        }
                    });
                }

                @Override
                public void onSuccess() {
                    ffmpegReady = true;
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            appendLog("FFmpeg 已就绪");
                        }
                    });
                }

                @Override
                public void onStart() {
                }

                @Override
                public void onFinish() {
                }
            });
        } catch (Exception e) {
            appendLog("FFmpeg 初始化失败：" + e.getMessage());
            toast("FFmpeg 初始化失败：" + e.getMessage());
        }
    }

    private void setSpinner(Spinner spinner, String[] items) {
        ArrayAdapter<String> adapter = new ArrayAdapter<String>(
                this, android.R.layout.simple_spinner_item, items);
        adapter.setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item);
        spinner.setAdapter(adapter);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (resultCode != RESULT_OK) {
            return;
        }
        try {
            if (requestCode == REQ_BATCH_ADD) {
                List<Uri> uris = new ArrayList<Uri>();
                ClipData clip = data != null ? data.getClipData() : null;
                if (clip != null) {
                    for (int i = 0; i < clip.getItemCount(); i++) {
                        uris.add(clip.getItemAt(i).getUri());
                    }
                } else if (data != null && data.getData() != null) {
                    uris.add(data.getData());
                }
                for (Uri uri : uris) {
                    String name = queryName(uri);
                    String path = copyToCache(uri, "video", name);
                    BatchItem item = probeBatchItem(path, name);
                    batchItems.add(item);
                }
                batchAdapter.notifyDataSetChanged();
                updateBatchStatus();
            } else if (requestCode == REQ_BATCH_AUDIO) {
                Uri uri = data != null ? data.getData() : null;
                if (uri != null && batchAudioForIndex >= 0 && batchAudioForIndex < batchItems.size()) {
                    String name = queryName(uri);
                    String path = copyToCache(uri, "audio", name);
                    BatchItem item = batchItems.get(batchAudioForIndex);
                    item.audioPath = path;
                    item.audioName = name;
                    batchAudioForIndex = -1;
                    batchAdapter.notifyDataSetChanged();
                }
            } else {
                if (data == null || data.getData() == null) {
                    return;
                }
                Uri uri = data.getData();
                if (requestCode == REQ_VIDEO) {
                    String name = queryName(uri);
                    String path = copyToCache(uri, "video", name);
                    loadVideoInfo(path, name);
                } else if (requestCode == REQ_AUDIO) {
                    String name = queryName(uri);
                    audioPath = copyToCache(uri, "audio", name);
                    audioName = name;
                    tvAudioName.setText("替换音频：" + name);
                }
            }
        } catch (Exception e) {
            toast("读取文件失败：" + e.getMessage());
        }
    }

    private String queryName(Uri uri) {
        String name = null;
        if ("content".equals(uri.getScheme())) {
            Cursor cursor = getContentResolver().query(uri, null, null, null, null);
            if (cursor != null) {
                try {
                    if (cursor.moveToFirst()) {
                        int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                        if (index >= 0) {
                            name = cursor.getString(index);
                        }
                    }
                } finally {
                    cursor.close();
                }
            }
        }
        if (name == null) {
            name = uri.getLastPathSegment();
        }
        if (name == null) {
            name = "input";
        }
        return name.replaceAll("[\\\\/:*?\"<>|\\s]+", "_");
    }

    private String copyToCache(Uri uri, String prefix, String name) throws IOException {
        File dir = new File(getCacheDir(), "input");
        if (!dir.exists() && !dir.mkdirs()) {
            throw new IOException("无法创建缓存目录");
        }
        File out = new File(dir, prefix + "_" + name);
        InputStream in = getContentResolver().openInputStream(uri);
        FileOutputStream fos = new FileOutputStream(out);
        byte[] buffer = new byte[8192];
        int read;
        while ((read = in.read(buffer)) != -1) {
            fos.write(buffer, 0, read);
        }
        in.close();
        fos.close();
        return out.getAbsolutePath();
    }

    private void loadVideoInfo(String path, String name) {
        videoPath = path;
        videoName = name;
        durationSec = 0;
        hasAudio = true;
        int width = 0;
        int height = 0;
        try {
            MediaMetadataRetriever retriever = new MediaMetadataRetriever();
            retriever.setDataSource(path);
            String duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
            String w = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH);
            String h = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT);
            String audio = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO);
            if (duration != null) {
                durationSec = Integer.parseInt(duration) / 1000;
            }
            if (w != null) {
                width = Integer.parseInt(w);
            }
            if (h != null) {
                height = Integer.parseInt(h);
            }
            hasAudio = audio != null;
            retriever.release();
        } catch (Exception ignored) {
        }
        tvVideoInfo.setText(name + "   " + width + "×" + height + "   "
                + durationSec + " 秒   " + (hasAudio ? "有音轨" : "无音轨"));
        etEnd.setText(formatTime(durationSec));
        appendLog("已选择视频：" + name);
    }

    private static String formatTime(double seconds) {
        int total = (int) seconds;
        int h = total / 3600;
        int m = (total % 3600) / 60;
        int s = total % 60;
        if (h > 0) {
            return String.format("%02d:%02d:%02d", h, m, s);
        }
        return String.format("%02d:%02d", m, s);
    }

    private double parseTime(String text) {
        if (text == null) {
            return 0;
        }
        String value = text.trim();
        if (value.length() == 0) {
            return 0;
        }
        double total = 0;
        for (String part : value.split(":")) {
            try {
                total = total * 60 + Double.parseDouble(part.trim());
            } catch (NumberFormatException e) {
                return 0;
            }
        }
        return total;
    }

    private boolean hasStoragePermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE)
                    == PackageManager.PERMISSION_GRANTED;
        }
        return true;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQ_PERM_LAUNCH) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                updateOutputDirLabel();
                toast("已获得存储权限");
            } else {
                toast("未授权存储权限，将保存到应用私有目录");
            }
            return;
        }
        if (requestCode == REQ_PERM) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                if (permRequestedForBatch) {
                    permRequestedForBatch = false;
                    startBatchConvert();
                } else {
                    startConvert();
                }
            } else {
                toast("没有存储权限，无法写入输出目录");
            }
        }
    }

    private static final String FFMPEG_ASSET_VERSION = "6.1.1-amv";

    /**
     * 升级安装时 App 私有目录里可能还缓存着旧版 ffmpeg（不支持 AMV），
     * 这里按版本标记清掉缓存，让库重新从 assets 解压新二进制。
     */
    private void invalidateOldFfmpegBinary() {
        String cached = prefs.getString("ffmpeg_bin_ver", null);
        if (FFMPEG_ASSET_VERSION.equals(cached)) {
            return;
        }
        File cachedBinary = new File(getFilesDir(), "ffmpeg");
        if (cachedBinary.exists()) {
            cachedBinary.delete();
        }
        prefs.edit().putString("ffmpeg_bin_ver", FFMPEG_ASSET_VERSION).commit();
    }

    private void updateOutputDirLabel() {
        if (tvOutputDir == null) {
            return;
        }
        tvOutputDir.setText(resolveOutputDir().getAbsolutePath());
    }

    private void showPickOutputDir() {
        final File[] cur = new File[]{outputDirOverride != null
                ? new File(outputDirOverride) : resolveOutputDir()};
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        final TextView tvPath = new TextView(this);
        tvPath.setTextSize(12);
        tvPath.setTextColor(0xFF3E4C59);
        tvPath.setPadding(dp(16), dp(8), dp(16), dp(6));
        final ListView list = new ListView(this);
        final ArrayAdapter<String> adapter = new ArrayAdapter<String>(
                this, android.R.layout.simple_list_item_1, new ArrayList<String>());
        list.setAdapter(adapter);
        box.addView(tvPath);
        box.addView(list, new LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, dp(280)));

        final Runnable refresh = new Runnable() {
            @Override
            public void run() {
                adapter.clear();
                File parent = cur[0].getParentFile();
                if (parent != null) {
                    adapter.add(".. 上级目录");
                }
                File[] subs = cur[0].listFiles();
                if (subs != null) {
                    java.util.Arrays.sort(subs, new java.util.Comparator<File>() {
                        @Override
                        public int compare(File a, File b) {
                            return a.getName().compareToIgnoreCase(b.getName());
                        }
                    });
                    for (File f : subs) {
                        if (f.isDirectory() && !f.getName().startsWith(".")) {
                            adapter.add(f.getName() + "/");
                        }
                    }
                }
                tvPath.setText(cur[0].getAbsolutePath());
            }
        };
        refresh.run();

        list.setOnItemClickListener(new android.widget.AdapterView.OnItemClickListener() {
            @Override
            public void onItemClick(android.widget.AdapterView<?> parent, View view,
                                    int position, long id) {
                File parentDir = cur[0].getParentFile();
                if (parentDir != null && position == 0) {
                    cur[0] = parentDir;
                } else {
                    String name = adapter.getItem(position);
                    File target = new File(cur[0], name.substring(0, name.length() - 1));
                    if (target.isDirectory()) {
                        cur[0] = target;
                    }
                }
                refresh.run();
            }
        });

        final AlertDialog dialog = new AlertDialog.Builder(this)
                .setTitle("选择输出目录")
                .setView(box)
                .setPositiveButton("选择此目录", null)
                .setNegativeButton("取消", null)
                .setNeutralButton("恢复默认", null)
                .create();
        dialog.setOnShowListener(new android.content.DialogInterface.OnShowListener() {
            @Override
            public void onShow(android.content.DialogInterface d) {
                final AlertDialog ad = (AlertDialog) d;
                ad.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        File dir = cur[0];
                        if (!isDirWritable(dir)) {
                            toast("该目录不可写，请换一个或先授予存储权限");
                            return;
                        }
                        outputDirOverride = dir.getAbsolutePath();
                        prefs.edit().putString("output_dir", outputDirOverride).apply();
                        updateOutputDirLabel();
                        toast("输出目录：" + outputDirOverride);
                        ad.dismiss();
                    }
                });
                ad.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(new View.OnClickListener() {
                    @Override
                    public void onClick(View v) {
                        outputDirOverride = null;
                        prefs.edit().remove("output_dir").apply();
                        updateOutputDirLabel();
                        toast("已恢复默认输出目录");
                        ad.dismiss();
                    }
                });
            }
        });
        dialog.show();
    }

    private File resolveOutputDir() {
        File dir;
        if (outputDirOverride != null) {
            dir = new File(outputDirOverride);
        } else {
            dir = new File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES),
                    "AMV");
        }
        if (dir.exists() || dir.mkdirs()) {
            return dir;
        }
        File fallback = new File(getExternalFilesDir(null), "AMV");
        fallback.mkdirs();
        return fallback;
    }

    /** 真实写入探测：确认目录可创建并写入临时文件。 */
    private boolean isDirWritable(File dir) {
        try {
            if (!dir.exists() && !dir.mkdirs()) {
                return false;
            }
            File probe = new File(dir, ".amv_write_probe");
            if (!probe.createNewFile()) {
                return false;
            }
            probe.delete();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /** 用户自选了输出目录时，转换前校验可写性，失败给出明确提示。 */
    private boolean checkSelectedOutputDir() {
        if (outputDirOverride == null) {
            return true;
        }
        if (isDirWritable(new File(outputDirOverride))) {
            return true;
        }
        toast("所选输出目录不可写：\n" + outputDirOverride + "\n请更换目录或授予存储权限");
        return false;
    }

    private void startConvert() {
        if (running) {
            return;
        }
        if (videoPath == null) {
            toast("请先选择视频");
            return;
        }
        if (!ffmpegReady) {
            toast("FFmpeg 还在加载，请稍候");
            return;
        }
        if (!hasStoragePermission()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                permRequestedForBatch = false;
                requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE}, REQ_PERM);
            }
            return;
        }
        if (!checkSelectedOutputDir()) {
            return;
        }

        boolean isAvi = rgFormat.getCheckedRadioButtonId() == R.id.rbAvi;
        int[][] dims = isAvi ? AVI_DIMS : AMV_DIMS;
        int sizeIndex = spSize.getSelectedItemPosition();
        int width = dims[sizeIndex][0];
        int height = dims[sizeIndex][1];

        double startSec = cbCut.isChecked() ? parseTime(etStart.getText().toString()) : 0;
        double endSec = cbCut.isChecked() ? parseTime(etEnd.getText().toString()) : 0;
        if (endSec <= 0) {
            endSec = durationSec;
        }
        totalSec = endSec > startSec ? endSec - startSec : durationSec;

        String base = videoName.replaceAll("\\.[^.]+$", "").replaceAll("[\\\\/:*?\"<>|\\s]+", "_");
        String ext = isAvi ? "avi" : "amv";
        File outDir = resolveOutputDir();
        File outputFile = new File(outDir, base + "_" + width + "x" + height + "." + ext);
        if (outputFile.exists()) {
            outputFile.delete();
        }

        final String[] command = buildCommand(videoPath, audioPath, durationSec, hasAudio, videoName, outputFile);
        running = true;
        progress.setProgress(0);
        tvStatus.setText("正在转换…");
        logBuffer.setLength(0);
        appendLog("命令: ffmpeg " + joinCommand(command));
        btnConvert.setEnabled(false);

        runFfmpeg(command, outputFile, false, null);
    }

    private String[] buildCommand(String vPath, String aPath, int durSec, boolean hAudio,
                                  String vName, File outFile) {
        boolean isAvi = rgFormat.getCheckedRadioButtonId() == R.id.rbAvi;
        int[][] dims = isAvi ? AVI_DIMS : AMV_DIMS;
        int sizeIndex = spSize.getSelectedItemPosition();
        int width = dims[sizeIndex][0];
        int height = dims[sizeIndex][1];

        int fps = FPS_VALUES[spFps.getSelectedItemPosition()];
        int q = QUALITY_Q[spQuality.getSelectedItemPosition()];
        int transformIndex = spTransform.getSelectedItemPosition();

        double startSec = cbCut.isChecked() ? parseTime(etStart.getText().toString()) : 0;
        double endSec = cbCut.isChecked() ? parseTime(etEnd.getText().toString()) : 0;
        if (endSec <= 0) {
            endSec = durSec;
        }
        totalSec = endSec > startSec ? endSec - startSec : durSec;

        List<String> cmd = new ArrayList<String>();
        cmd.add("-y");
        if (startSec > 0) {
            cmd.add("-ss");
            cmd.add(formatTime(startSec));
        }
        cmd.add("-i");
        cmd.add(vPath);
        if (aPath != null) {
            cmd.add("-i");
            cmd.add(aPath);
        } else if (!hAudio) {
            cmd.add("-f");
            cmd.add("lavfi");
            cmd.add("-i");
            cmd.add("anullsrc=r=22050:cl=mono");
        }

        cmd.add("-map");
        cmd.add("0:v:0");
        cmd.add("-map");
        cmd.add(aPath != null ? "1:a:0" : (hAudio ? "0:a:0" : "1:a:0"));

        StringBuilder vf = new StringBuilder();
        String transformFilter = TRANSFORM_FILTERS[transformIndex];
        if (transformFilter.length() > 0) {
            vf.append(transformFilter).append(",");
        }
        vf.append("scale=").append(width).append(":").append(height)
                .append(":force_original_aspect_ratio=decrease,");
        vf.append("pad=").append(width).append(":").append(height)
                .append(":(ow-iw)/2:(oh-ih)/2:color=black,setsar=1");
        cmd.add("-vf");
        cmd.add(vf.toString());
        cmd.add("-r");
        cmd.add(String.valueOf(fps));
        if (cbVideoSync.isChecked()) {
            cmd.add("-vsync");
            cmd.add("cfr");
        }
        if (!isAvi) {
            cmd.add("-strict");
            cmd.add("-1");
        }
        cmd.add("-c:v");
        cmd.add(isAvi ? "mpeg4" : "amv");
        cmd.add("-q:v");
        cmd.add(String.valueOf(q));
        cmd.add("-pix_fmt");
        cmd.add(isAvi ? "yuv420p" : "yuvj420p");
        if (!isAvi) {
            cmd.add("-c:a");
            cmd.add("adpcm_ima_amv");
            cmd.add("-block_size");
            cmd.add(String.valueOf(22050 / fps));
            cmd.add("-ar");
            cmd.add("22050");
            cmd.add("-ac");
            cmd.add("1");
        } else {
            cmd.add("-c:a");
            cmd.add("pcm_s16le");
            cmd.add("-ar");
            cmd.add("22050");
            cmd.add("-ac");
            cmd.add("1");
            cmd.add("-vtag");
            cmd.add("XVID");
        }
        if (cbAudioSync.isChecked()) {
            cmd.add("-af");
            cmd.add("aresample=async=1:first_pts=0");
        }
        if (totalSec > 0 && totalSec < durSec) {
            cmd.add("-t");
            cmd.add(String.valueOf((int) Math.ceil(totalSec)));
        }
        cmd.add("-shortest");
        cmd.add(outFile.getAbsolutePath());
        return cmd.toArray(new String[cmd.size()]);
    }

    private void runFfmpeg(final String[] command, final File outputFile, final boolean isBatch,
                           final Runnable onDone) {
        try {
            ffmpeg.execute(command, new ExecuteBinaryResponseHandler() {
                @Override
                public void onStart() {
                }

                @Override
                public void onProgress(String message) {
                    appendLog(message.trim());
                    updateProgress(message);
                }

                @Override
                public void onFailure(String message) {
                    if (message != null && message.length() > 0) {
                        appendLog(message.trim());
                    }
                }

                @Override
                public void onSuccess(String message) {
                    if (message != null && message.length() > 0) {
                        appendLog(message.trim());
                    }
                }

                @Override
                public void onFinish() {
                    final boolean ok = outputFile.exists() && outputFile.length() > 0;
                    runOnUiThread(new Runnable() {
                        @Override
                        public void run() {
                            if (isBatch) {
                                if (onDone != null) {
                                    onDone.run();
                                }
                            } else {
                                running = false;
                                btnConvert.setEnabled(true);
                                if (ok) {
                                    progress.setProgress(100);
                                    tvStatus.setText("转换完成：" + outputFile.getName()
                                            + "（" + formatSize(outputFile.length()) + "）");
                                    appendLog("输出：" + outputFile.getAbsolutePath());
                                    if (cbAutoPlay.isChecked()) {
                                        openOutput(outputFile);
                                    }
                                } else {
                                    tvStatus.setText("转换失败，请查看日志");
                                }
                            }
                        }
                    });
                }
            });
        } catch (Exception e) {
            appendLog("启动失败：" + e.getMessage());
            if (isBatch) {
                if (onDone != null) {
                    onDone.run();
                }
            } else {
                running = false;
                btnConvert.setEnabled(true);
                tvStatus.setText("转换失败");
            }
        }
    }

    private BatchItem probeBatchItem(String path, String name) {
        BatchItem item = new BatchItem();
        item.videoPath = path;
        item.videoName = name;
        item.durationSec = 5; // 保底值，防止 totalSec=0 导致进度永远不更新
        item.hasAudio = true;
        try {
            MediaMetadataRetriever retriever = new MediaMetadataRetriever();
            retriever.setDataSource(path);
            String d = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION);
            String a = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_HAS_AUDIO);
            if (d != null) {
                int sec = Integer.parseInt(d) / 1000;
                if (sec > 0) {
                    item.durationSec = sec;
                }
            }
            item.hasAudio = a != null;
            retriever.release();
        } catch (Exception ignored) {
        }
        return item;
    }

    private void updateBatchStatus() {
        int total = batchItems.size();
        int checked = 0;
        int done = 0;
        for (BatchItem it : batchItems) {
            if (it.checked) {
                checked++;
            }
            if (it.status == 2) {
                done++;
            }
        }
        tvBatchStatus.setText("共 " + total + " 个，已选 " + checked + " 个，已完成 " + done + " 个");
        int percent = checked > 0 ? done * 100 / checked : 0;
        progressBatch.setProgress(percent);
    }

    private File outputFileFor(BatchItem item) {
        boolean isAvi = rgFormat.getCheckedRadioButtonId() == R.id.rbAvi;
        int[][] dims = isAvi ? AVI_DIMS : AMV_DIMS;
        int sizeIndex = spSize.getSelectedItemPosition();
        int width = dims[sizeIndex][0];
        int height = dims[sizeIndex][1];
        String base = item.videoName.replaceAll("\\.[^.]+$", "")
                .replaceAll("[\\\\/:*?\"<>|\\s]+", "_");
        String ext = isAvi ? "avi" : "amv";
        File outDir = resolveOutputDir();
        return new File(outDir, base + "_" + width + "x" + height + "." + ext);
    }

    private void pickBatchAudio(int index) {
        batchAudioForIndex = index;
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.setType("audio/*");
        startActivityForResult(Intent.createChooser(intent, "选择替换音频"), REQ_BATCH_AUDIO);
    }

    private void startBatchConvert() {
        if (batchRunning) {
            return;
        }
        if (!ffmpegReady) {
            toast("FFmpeg 还在加载，请稍候");
            return;
        }
        if (!hasStoragePermission()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                permRequestedForBatch = true;
                requestPermissions(new String[]{Manifest.permission.WRITE_EXTERNAL_STORAGE}, REQ_PERM);
            }
            return;
        }
        if (!checkSelectedOutputDir()) {
            return;
        }
        int pending = 0;
        for (BatchItem it : batchItems) {
            if (it.checked && it.status != 2) {
                pending++;
            }
        }
        if (pending == 0) {
            toast("没有待转换的勾选项");
            return;
        }
        batchRunning = true;
        btnBatchConvert.setEnabled(false);
        logBuffer.setLength(0);
        appendLog("批量转换开始，共 " + pending + " 个");
        runBatchNext(0);
    }

    private void runBatchNext(int from) {
        int idx = -1;
        for (int i = from; i < batchItems.size(); i++) {
            BatchItem it = batchItems.get(i);
            if (it.checked && it.status != 2) {
                idx = i;
                break;
            }
        }
        if (idx < 0) {
            batchRunning = false;
            btnBatchConvert.setEnabled(true);
            updateBatchStatus();
            appendLog("批量转换完成");
            return;
        }
        final BatchItem item = batchItems.get(idx);
        item.status = 1;
        item.progress = 0;
        currentBatchItem = item;
        totalSec = item.durationSec > 0 ? item.durationSec : 5; // 显式设置，保证进度计算生效
        batchAdapter.notifyDataSetChanged();
        final File outputFile = outputFileFor(item);
        if (outputFile.exists()) {
            outputFile.delete();
        }
        tvBatchStatus.setText("正在转换：" + item.videoName);
        final String[] command = buildCommand(item.videoPath, item.audioPath,
                item.durationSec, item.hasAudio, item.videoName, outputFile);
        appendLog("命令: ffmpeg " + joinCommand(command));
        final int currentIdx = idx;
        runFfmpeg(command, outputFile, true, new Runnable() {
            @Override
            public void run() {
                boolean ok = outputFile.exists() && outputFile.length() > 0;
                item.status = ok ? 2 : 3;
                item.progress = ok ? 100 : item.progress;
                currentBatchItem = null;
                batchAdapter.notifyDataSetChanged();
                updateBatchStatus();
                runBatchNext(currentIdx + 1);
            }
        });
    }

    private class BatchAdapter extends BaseAdapter {
        private final String[] statusText = {"未处理", "转换中", "已完成", "失败"};
        private final int[] statusColor = {0xFF52606D, 0xFFFF9800, 0xFF43A047, 0xFFE53935};

        @Override
        public int getCount() {
            return batchItems.size();
        }

        @Override
        public Object getItem(int position) {
            return batchItems.get(position);
        }

        @Override
        public long getItemId(int position) {
            return position;
        }

        @Override
        public View getView(final int position, View convertView, ViewGroup parent) {
            if (convertView == null) {
                convertView = LayoutInflater.from(MainActivity.this)
                        .inflate(R.layout.row_batch, parent, false);
            }
            final BatchItem item = batchItems.get(position);
            final CheckBox cb = (CheckBox) convertView.findViewById(R.id.cbRow);
            cb.setOnCheckedChangeListener(null);
            cb.setChecked(item.checked);
            cb.setOnCheckedChangeListener(new CompoundButton.OnCheckedChangeListener() {
                @Override
                public void onCheckedChanged(CompoundButton buttonView, boolean isChecked) {
                    item.checked = isChecked;
                    updateBatchStatus();
                }
            });
            TextView tvName = (TextView) convertView.findViewById(R.id.tvRowName);
            TextView tvAudio = (TextView) convertView.findViewById(R.id.tvRowAudio);
            TextView tvStatus = (TextView) convertView.findViewById(R.id.tvRowStatus);
            TextView tvTime = (TextView) convertView.findViewById(R.id.tvRowTime);
            ProgressBar pbRow = (ProgressBar) convertView.findViewById(R.id.pbRow);
            tvName.setText(item.videoName);
            tvAudio.setText(item.audioName != null
                    ? "音频：" + item.audioName
                    : "（点击此处替换音频）");
            if (item.status == 1) {
                tvStatus.setText(item.progress + "%");
                pbRow.setVisibility(View.VISIBLE);
                pbRow.setProgress(item.progress);
            } else {
                tvStatus.setText(statusText[item.status]);
                pbRow.setVisibility(View.GONE);
            }
            tvStatus.setTextColor(statusColor[item.status]);
            tvTime.setText(formatTime(item.durationSec));
            convertView.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    pickBatchAudio(position);
                }
            });
            return convertView;
        }
    }

    private String joinCommand(String[] command) {
        StringBuilder builder = new StringBuilder();
        for (String part : command) {
            builder.append(part).append(' ');
        }
        return builder.toString();
    }

    private void updateProgress(String message) {
        int percent = -1;
        if (totalSec > 0) {
            int index = message.indexOf("time=");
            if (index > 0) {
                String rest = message.substring(index + 5);
                int end = rest.indexOf(' ');
                String timeText = end > 0 ? rest.substring(0, end) : rest;
                double seconds = parseTime(timeText);
                percent = (int) Math.min(100, seconds / totalSec * 100);
            }
        }
        if (percent < 0) {
            // FFmpeg 还没输出 time= 行，用已写文件大小做保守估算
            percent = estimateProgressByOutputSize();
        }
        if (percent < 0) {
            return;
        }
        final int finalPercent = percent;
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                progress.setProgress(finalPercent);
                if (currentBatchItem != null) {
                    currentBatchItem.progress = finalPercent;
                    batchAdapter.notifyDataSetChanged();
                }
            }
        });
    }

    /** 当 FFmpeg 还没输出 time= 时，根据当前输出文件大小估算进度（保守值，不超过 40%）。 */
    private int estimateProgressByOutputSize() {
        if (currentBatchItem == null) {
            return -1;
        }
        try {
            File out = outputFileFor(currentBatchItem);
            long size = out.exists() ? out.length() : 0;
            if (size <= 0) {
                return -1;
            }
            // 输出文件大小 / 输入文件大小 × 40，封顶 40（因为 AMV 通常比源文件小）
            long inSize = new File(currentBatchItem.videoPath).length();
            if (inSize > 0) {
                int pct = (int) Math.min(40, size * 40L / inSize);
                return Math.max(pct, 1);
            }
            // 完全估算：有输出就是 5%
            return 5;
        } catch (Exception e) {
            return -1;
        }
    }

    private void openOutput(File file) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) {
            try {
                Intent intent = new Intent(Intent.ACTION_VIEW);
                intent.setDataAndType(Uri.fromFile(file), "video/*");
                startActivity(intent);
            } catch (Exception e) {
                toast("没有可用的播放器");
            }
        } else {
            toast("文件已保存：" + file.getName());
        }
    }

    private static String formatSize(long bytes) {
        if (bytes >= 1048576) {
            return String.format("%.2f MB", bytes / 1048576.0);
        }
        return String.format("%.0f KB", bytes / 1024.0);
    }

    private void appendLog(final String line) {
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (line == null || line.length() == 0) {
                    return;
                }
                logBuffer.append(line).append('\n');
                if (logBuffer.length() > 12000) {
                    logBuffer.delete(0, logBuffer.length() - 12000);
                }
                tvLog.setText(logBuffer.toString());
                tvLog.scrollTo(0, tvLog.getHeight());
            }
        });
    }

    private void showAbout() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        layout.setPadding(dp(24), dp(24), dp(24), dp(8));

        ImageView avatar = new ImageView(this);
        avatar.setImageResource(R.drawable.avatar);
        LinearLayout.LayoutParams avatarParams =
                new LinearLayout.LayoutParams(dp(110), dp(110));
        avatarParams.gravity = Gravity.CENTER_HORIZONTAL;
        avatar.setLayoutParams(avatarParams);
        avatar.setScaleType(ImageView.ScaleType.CENTER_CROP);
        layout.addView(avatar);

        TextView name = new TextView(this);
        name.setText("擅长捉弄人的王同学");
        name.setTextSize(18);
        name.setGravity(Gravity.CENTER_HORIZONTAL);
        name.setPadding(0, dp(14), 0, dp(2));
        layout.addView(name);

        TextView role = new TextView(this);
        role.setText("视频转 AMV 作者");
        role.setTextSize(12);
        role.setGravity(Gravity.CENTER_HORIZONTAL);
        layout.addView(role);

        TextView contact = new TextView(this);
        contact.setText("\nQQ：3418696565\nX：hoshino_mion");
        contact.setTextSize(14);
        contact.setGravity(Gravity.CENTER_HORIZONTAL);
        layout.addView(contact);

        new AlertDialog.Builder(this)
                .setTitle("关于软件")
                .setView(layout)
                .setPositiveButton("关闭", null)
                .show();
    }

    private int dp(int value) {
        return (int) (value * getResources().getDisplayMetrics().density);
    }

    private void toast(String message) {
        if (!isFinishing()) {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
        }
    }
}
